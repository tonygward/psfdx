// Delivery verifiers. Each returns { ok, evidence, missing[] } and reads only through the injected `io`, so this module
// holds no credentials and writes nothing. Downloads are not tested.
import { sectionFor } from '../../scripts/release/bump-lib.mjs';

// The same rule as CI and CD - Bump version: a change that is only Markdown, prompts, docs, tools or images has nothing
// to release. tests/DocsOnly.Tests.ps1-style drift is caught by a test that compares this with the workflow files.
export const DOCS_ONLY_PATTERNS = [/\.md$/, /^prompts\//, /^docs\//, /^tools\//, /^images\//, /\.(?:png|jpe?g|gif|svg)$/];
export const isDocsOnly = files => Array.isArray(files) && files.length > 0 && files.every(file => DOCS_ONLY_PATTERNS.some(p => p.test(file)));

export const RELEASE_SUBJECT = /^\[release\] (\d+\.\d+\.\d+)$/;
export const assetName = version => `psfdx-${version}.zip`;
const result = (missing, evidence = {}) => ({ ok: missing.length === 0, evidence, missing });
const normal = text => String(text ?? '').replace(/\r\n/g, '\n').trim();

// 1. Merge: the pull request merged into the base branch; record the merge commit.
export async function verifyMerge(io, delivery) {
  const pull = await io.pull(delivery.repository, delivery.pull);
  if (pull?.state !== 'MERGED' || !pull.mergeSha) return result(['Pull request is not merged']);
  return result([], { number: delivery.pull, url: pull.url, mergeSha: pull.mergeSha });
}

// 2. Version: the first `[release] X.Y.Z` commit on main after the merge commit. Two tasks that merge before one bump
// both land in the same release, because the first release commit after each merge commit is the evidence for both.
export async function verifyVersion(io, repository, mergeSha) {
  const commits = await io.commitsAfter(repository, mergeSha); // oldest first, descendants of the merge commit
  const bump = (Array.isArray(commits) ? commits : []).find(c => RELEASE_SUBJECT.test(c.subject ?? ''));
  if (!bump) return result(['No [release] commit on main after the merge yet']);
  return result([], { version: RELEASE_SUBJECT.exec(bump.subject)[1], bumpSha: bump.sha });
}

// 3. Release: published, not a draft or pre-release, its tag on the bump commit, exactly one non-empty asset.
export async function verifyRelease(io, repository, version, bumpSha) {
  const tag = `v${version}`;
  const release = await io.release(repository, tag);
  if (!release) return result([`No GitHub release ${tag} yet`]);
  const missing = [];
  if (release.isDraft) missing.push(`Release ${tag} is still a draft`);
  if (release.isPrerelease) missing.push(`Release ${tag} is marked as a pre-release`);
  const tagSha = await io.tagCommit(repository, tag);
  if (tagSha !== bumpSha) missing.push(`Tag ${tag} points at ${String(tagSha).slice(0, 7)}, not the bump commit ${String(bumpSha).slice(0, 7)}`);
  const assets = Array.isArray(release.assets) ? release.assets : [];
  if (assets.length !== 1 || assets[0].name !== assetName(version)) missing.push(`Release ${tag} must have exactly one asset, ${assetName(version)}; it has ${assets.length ? assets.map(a => a.name).join(', ') : 'none'}`);
  else if (!(assets[0].size > 0)) missing.push(`Release asset ${assetName(version)} is empty`);
  return result(missing, { tag, url: release.url, version, asset: assetName(version), bumpSha, body: release.body });
}

// 4. Notes: non-empty and equal to that version's changelog section at the tag.
export async function verifyNotes(io, repository, version, release) {
  const notes = normal(release.body);
  if (!notes) return result([`Release v${version} has no notes`]);
  const changelog = await io.fileAt(repository, 'CHANGELOG.md', `v${version}`);
  const expected = sectionFor(String(changelog ?? ''), version);
  if (expected === null) return result([`CHANGELOG.md at v${version} has no section for ${version}`]);
  if (notes !== normal(expected)) return result([`Release notes for v${version} do not match its CHANGELOG.md section`]);
  return result([]);
}

// 5. Prompt archived: the task's prompt is in prompts/done/ on main (generated or hand-written).
export async function verifyPromptArchived(io, repository, file) {
  if (!file) return result([]);
  const name = file.split('/').pop();
  return (await io.fileExists(repository, `prompts/done/${name}`, 'main')) ? result([]) : result([`Canonical prompt is not archived in prompts/done/ yet: ${name}`]);
}

// 6. PowerShell Gallery: only when delivery.psGallery.enabled is true (AUTO-11 turns it on).
export async function verifyGallery(io, version) {
  return (await io.galleryHas(version)) ? result([], { url: `https://www.powershellgallery.com/packages/psfdx/${version}` }) : result([`The psfdx package ${version} is not on the PowerShell Gallery yet`]);
}

// The real readers. `gh(args)` returns stdout and holds a token that can read the repository; `fetchJson` is only used for the Gallery.
export function readIo(gh, { fetchFn = globalThis.fetch } = {}) {
  const json = async args => JSON.parse(await gh(args));
  const missing = error => /404|not found/i.test(String(error?.message ?? error) + String(error?.stderr ?? ''));
  return {
    pull: async (repository, number) => {
      const pull = await json(['pr', 'view', String(number), '--repo', repository, '--json', 'state,mergeCommit,url']);
      return { state: pull.state, mergeSha: pull.mergeCommit?.oid ?? null, url: pull.url };
    },
    pullFiles: async (repository, number) => (await gh(['api', '--paginate', `repos/${repository}/pulls/${number}/files`, '--jq', '.[].filename'])).split('\n').filter(Boolean),
    // Commits on main after the merge commit, oldest first (the compare API lists them in that order).
    commitsAfter: async (repository, mergeSha) => (await gh(['api', `repos/${repository}/compare/${mergeSha}...main`, '--jq', '.commits[] | {sha: .sha, subject: (.commit.message | split("\\n")[0])}'])).split('\n').filter(Boolean).map(line => JSON.parse(line)),
    release: async (repository, tag) => {
      try { return await json(['release', 'view', tag, '--repo', repository, '--json', 'tagName,url,isDraft,isPrerelease,body,assets']); }
      catch (error) { if (missing(error)) return null; throw error; }
    },
    tagCommit: async (repository, tag) => (await gh(['api', `repos/${repository}/commits/${tag}`, '--jq', '.sha'])).trim(),
    fileAt: async (repository, file, ref) => gh(['api', '-H', 'Accept: application/vnd.github.raw', `repos/${repository}/contents/${file}?ref=${ref}`]),
    fileExists: async (repository, file, ref) => {
      try { await gh(['api', `repos/${repository}/contents/${file}?ref=${ref}`, '--jq', '.path']); return true; }
      catch (error) { if (missing(error)) return false; throw error; }
    },
    galleryHas: async version => {
      const response = await fetchFn(`https://www.powershellgallery.com/api/v2/Packages(Id='psfdx',Version='${encodeURIComponent(version)}')`, { signal: AbortSignal.timeout(15000) });
      if (response.status === 200) return true;
      if (response.status === 404) return false;
      throw new Error(`PowerShell Gallery returned ${response.status}`);
    },
  };
}
