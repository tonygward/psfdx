// Pure decision logic for merging and archiving Matrix pull requests. No network, no git.
// The workflows fetch the facts with `gh` and call these functions from main (never from PR code).
import path from 'node:path';

export const BUILD_RUN = 'CI - Pester tests';
export const CORE_RUN = 'CI - Matrix orchestration tests';
export const REQUIRED_JOBS = [
  'Changes',
  'Pester (ubuntu, pwsh)',
  'Pester (windows, pwsh)',
  'Pester (windows, powershell 5.1)',
];
export const CORE_STATEMENT = 'Matrix core change: owner-approved lane';
export const ARCHIVE_STATEMENT = 'Housekeeping: archive merged prompt';

export const TASK_BRANCH = /^matrix\/(?:PSF|AUTO)-\d+(?:-[a-z0-9]+)*$/;
export const CORE_BRANCH = /^matrix\/core\/[a-z0-9]+(?:-[a-z0-9]+)*$/;
export const ARCHIVE_BRANCH = /^housekeeping\/archive-(?:PSF|AUTO)-\d+$/;

function safePath(file) {
  if (typeof file !== 'string' || !file || /[\\\x00-\x1f]/.test(file)) return false;
  return !file.split('/').some(part => part === '..' || part === '.' || part.startsWith('.'));
}

// Files a task pull request may change. Workflows, scripts, installers, VERSION and anything else need a person.
export function inScope(file) {
  if (!safePath(file)) return false;
  return /^psfdx[^/]*\//.test(file)
    || /^(?:tests|prompts|docs|images)\//.test(file)
    || ['README.md', 'CHANGELOG.md', 'modules.ps1'].includes(file);
}

// Matrix core lane: Matrix's own controller code, its tests, container configuration and the execution policy.
// The gate, workflows, scripts, the Dockerfile and the egress allow-list are never in any lane.
export function inCoreScope(file) {
  if (!safePath(file)) return false;
  if (/\.(exe|dll|cmd|bat|ps1|sh|cmake)$/i.test(file)) return false;
  return /^tools\/matrix\/(?:tests\/)?[A-Za-z0-9._-]+\.(?:mjs|json|md)$/.test(file)
    || /^tools\/matrix-linux\/(?:worker\.config\.json|README\.md)$/.test(file)
    || file === 'docs/execution-policy.md';
}

// The archive lane may only touch prompts.
export function inArchiveScope(file) {
  return safePath(file) && /^prompts\/(?:done\/)?[A-Za-z0-9._-]+\.md$/.test(file);
}

function commonChecks({ repository, pr, files }, scopeFn, scopeName, no) {
  if (!pr || pr.state !== 'OPEN') no('Pull request is not open');
  if (pr?.baseRefName !== 'main') no('Base branch is not main');
  if (pr?.headRepository !== repository) no('Pull request is from another repository');
  if (!Array.isArray(files) || files.length === 0 || files.length > 100) no('Unexpected number of changed files');
  else for (const file of files) if (!scopeFn(file)) no(`Changed file outside the ${scopeName} scope: ${String(file).slice(0, 120)}`);
}

function runChecks({ pr, run, jobs, otherRuns }, requiredRun, requiredJobs, no) {
  if (!run || run.conclusion !== 'success' || run.event !== 'pull_request' || run.name !== requiredRun) {
    no(`${requiredRun} has not succeeded for the pull request`);
  }
  if (run && pr && run.head_sha !== pr.headRefOid) no('Test result is for an older commit than the pull request head');
  const list = Array.isArray(jobs) ? jobs : [];
  if (requiredJobs.length > 0) {
    for (const name of requiredJobs) {
      const job = list.find(j => j.name === name);
      if (!job) no(`Required job not found: ${name}`);
      else if (job.conclusion !== 'success') no(`Required job did not succeed (${job.conclusion}): ${name}`);
    }
  }
  for (const other of Array.isArray(otherRuns) ? otherRuns : []) {
    if (/^(?:Housekeeping|Gate) - /.test(other.name ?? '')) continue; // advisory or this gate itself
    if (['failure', 'cancelled', 'timed_out', 'startup_failure'].includes(other.conclusion)) {
      no(`Another workflow run failed for this commit: ${String(other.name).slice(0, 80)}`);
    }
  }
}

// Returns { merge, reasons, lane }. Merge only when every rule holds; reasons explain a refusal.
export function evaluate(facts) {
  const { pr, files, agentLogin } = facts;
  const branch = pr?.headRefName ?? '';
  if (CORE_BRANCH.test(branch)) return evaluateCore(facts);
  if (ARCHIVE_BRANCH.test(branch)) return evaluateArchive(facts);

  const reasons = [];
  const no = reason => reasons.push(reason);
  commonChecks(facts, inScope, 'permitted', no);
  if (!TASK_BRANCH.test(branch)) no('Branch is not a Matrix branch');
  if (!agentLogin || pr?.author !== agentLogin) no('Pull request was not opened by the agent identity');
  if (!/^Matrix job: \S+/m.test(String(pr?.body ?? ''))) no('Description has no "Matrix job:" line written by the worker');
  runChecks(facts, BUILD_RUN, REQUIRED_JOBS, no);
  return { merge: reasons.length === 0, reasons, lane: 'task' };
}

function evaluateCore(facts) {
  const { pr, files, agentLogin } = facts;
  const reasons = [];
  const no = reason => reasons.push(reason);
  commonChecks(facts, inCoreScope, 'Matrix core', no);
  if (!agentLogin || pr?.author !== agentLogin) no('Pull request was not opened by the agent identity');
  if (!String(pr?.body ?? '').includes(CORE_STATEMENT)) no('Description does not carry the Matrix core change statement');
  // A Markdown-only change does not start the orchestration tests, so the quick CI run is its check.
  const docsOnly = Array.isArray(files) && files.length > 0 && files.every(f => typeof f === 'string' && /\.md$/.test(f));
  runChecks(facts, docsOnly ? BUILD_RUN : CORE_RUN, docsOnly ? REQUIRED_JOBS : [], no);
  return { merge: reasons.length === 0, reasons, lane: 'core' };
}

// Archive pull requests are opened by the archive workflow with RELEASE_TOKEN, so their author is the release identity, not the worker.
function evaluateArchive(facts) {
  const { pr, releaseLogin } = facts;
  const reasons = [];
  const no = reason => reasons.push(reason);
  commonChecks(facts, inArchiveScope, 'archive', no);
  if (!releaseLogin || pr?.author !== releaseLogin) no('Pull request was not opened by the release identity');
  if (!String(pr?.body ?? '').includes(ARCHIVE_STATEMENT)) no('Description does not carry the archive statement');
  runChecks(facts, BUILD_RUN, REQUIRED_JOBS, no);
  return { merge: reasons.length === 0, reasons, lane: 'archive' };
}

// matrix/AUTO-07-slug -> AUTO-07
export function promptIdFromBranch(branch) {
  const match = /^matrix\/((?:PSF|AUTO)-\d+)(?:-[a-z0-9]+)*$/.exec(branch ?? '');
  return match ? match[1] : null;
}

// prompts/x.md -> prompts/done/x.md. Refuses anything already archived or outside prompts/.
export function archivePath(file) {
  const match = /^prompts\/([^/]+\.md)$/.exec(file ?? '');
  return match && match[1] !== 'README.md' ? `prompts/done/${match[1]}` : null;
}

// The done/ folder is the completion record and the board owns status, so archiving removes any
// status, execution or model line from the front matter. Relative links inside the file are rebased
// because it moves one folder deeper.
export function markDone(text, oldFile, newFile) {
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  let normal = text.replace(/\r\n/g, '\n');
  if (oldFile && newFile) normal = rebaseLinks(normal, oldFile, newFile);
  if (normal.startsWith('---\n')) {
    const end = normal.indexOf('\n---\n', 4);
    if (end >= 0) {
      const head = normal.slice(4, end).split('\n').filter(line => !/^(status|execution|model):/.test(line));
      normal = `---\n${head.join('\n')}` + normal.slice(end);
    }
  }
  return normal.replace(/\n/g, eol);
}

const LINK = /\]\(([^)\s#]+)(#[^)\s]*)?\)/g;
const isExternal = link => /^[a-z][a-z0-9+.-]*:/i.test(link) || link.startsWith('/');

// Rewrites relative links in a file that moves, so they still resolve to the same targets.
export function rebaseLinks(text, oldFile, newFile) {
  const oldDir = path.posix.dirname(oldFile);
  const newDir = path.posix.dirname(newFile);
  return text.replace(LINK, (match, link, fragment = '') => {
    if (isExternal(link)) return match;
    const target = path.posix.normalize(path.posix.join(oldDir, link));
    return `](${path.posix.relative(newDir, target)}${fragment})`;
  });
}

// Rewrites links in other pages that pointed at the moved file, and GitHub blob links to it.
export function relinkMoved(text, fromFile, oldPath, newPath) {
  const dir = path.posix.dirname(fromFile);
  return text
    .replace(LINK, (match, link, fragment = '') => {
      if (isExternal(link)) return match;
      return path.posix.normalize(path.posix.join(dir, link)) === oldPath
        ? `](${path.posix.relative(dir, newPath)}${fragment})`
        : match;
    })
    .split(`/blob/main/${oldPath}`).join(`/blob/main/${newPath}`);
}
