// Which Claude Code version should the psfdx Matrix agent image carry?
// The pinned versions live in versions.json. `check` (run by Start-MatrixPsfdx.ps1 -Action Build) refuses anything that is not an
// exact stable version, and a Claude Code version outside the family the usage gate accepts (tools/matrix/usage.mjs). `decide` picks
// a newer version by these rules, chosen to keep supply-chain risk low while staying current:
//   - stable x.y.z only (no pre-releases), never a deprecated version, never one already rejected by a failed trial;
//   - never a downgrade, and never a new major version without an explicit owner flag;
//   - a version must be at least `minAgeDays` old, so a bad release is usually withdrawn or deprecated before Matrix takes it;
//   - never newer than the registry's `latest` tag.
// Pure and dependency-free so it can be tested without a network.
import { DEFAULT_MINIMUM_VERSION, versionSupported } from '../matrix/usage.mjs';

export const PACKAGE = '@anthropic-ai/claude-code';

export const parseVersion = v => {
  const m = /^(\d+)\.(\d+)\.(\d+)$/.exec(String(v ?? ''));
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
};

export function compareVersions(a, b) {
  const x = parseVersion(a), y = parseVersion(b);
  if (!x || !y) throw new Error(`Not a stable version: ${!x ? a : b}`);
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
  return 0;
}

const DAY = 86400000;

/**
 * registry: the npm document ({ 'dist-tags': { latest }, time: { [version]: iso }, versions: { [version]: { deprecated? } } }).
 * Returns { action: 'update' | 'none', target?, current, reason }.
 */
export function chooseVersion({ current, registry, now = Date.now(), minAgeDays = 3, rejected = [], allowMajor = false }) {
  const cur = parseVersion(current);
  if (!cur) throw new Error(`The current version "${current}" is not a stable x.y.z version`);
  const latest = registry?.['dist-tags']?.latest;
  if (!parseVersion(latest)) return { action: 'none', current, reason: 'The registry reports no stable latest version' };
  const times = registry.time ?? {}, versions = registry.versions ?? {};
  const eligible = [], waiting = [];
  for (const version of Object.keys(versions)) {
    const v = parseVersion(version);
    if (!v || compareVersions(version, current) <= 0 || compareVersions(version, latest) > 0) continue;
    if (versions[version]?.deprecated || rejected.includes(version)) continue;
    if (v[0] !== cur[0] && !allowMajor) continue;
    const published = Date.parse(times[version]);
    if (!Number.isFinite(published)) continue; // no trustworthy publish time: never guess
    if (now - published < minAgeDays * DAY) waiting.push({ version, readyAt: new Date(published + minAgeDays * DAY).toISOString() });
    else eligible.push(version);
  }
  if (eligible.length) {
    const target = eligible.sort(compareVersions).at(-1);
    return { action: 'update', target, current, reason: `${target} is newer than ${current}, stable, not deprecated, and at least ${minAgeDays} days old` };
  }
  if (waiting.length) {
    const next = waiting.sort((a, b) => compareVersions(a.version, b.version)).at(-1);
    return { action: 'none', current, reason: `${next.version} is newer but younger than ${minAgeDays} days; eligible from ${next.readyAt}` };
  }
  return { action: 'none', current, reason: 'Already on the newest eligible version' };
}

export async function fetchRegistry(fetchImpl = fetch, timeoutMs = 60000) {
  const response = await fetchImpl(`https://registry.npmjs.org/${PACKAGE.replace('/', '%2f')}`, { headers: { accept: 'application/json' }, signal: AbortSignal.timeout(timeoutMs) });
  if (!response.ok) throw new Error(`npm registry answered ${response.status}`);
  const doc = await response.json();
  if (doc?.name !== PACKAGE || typeof doc.versions !== 'object') throw new Error('Unexpected registry response');
  return doc;
}

// Validates the three pins. Returns { ok, problems[] }.
export function checkPins({ claude, powershell, pester }, minimum = DEFAULT_MINIMUM_VERSION) {
  const problems = [];
  const stable = (name, value) => { if (!parseVersion(value)) problems.push(`${name} must be an exact stable x.y.z version, got "${value ?? ''}"`); };
  stable('Claude Code', claude); stable('PowerShell', powershell); stable('Pester', pester);
  if (parseVersion(claude) && !versionSupported(`${claude} (Claude Code)`, minimum)) {
    problems.push(`Claude Code ${claude} is outside the family the usage gate verified (${minimum} or later in the same major and minor family)`);
  }
  if (parseVersion(powershell) && parseVersion(powershell)[0] !== 7) problems.push(`PowerShell must be 7.x, got ${powershell}`);
  if (parseVersion(pester) && parseVersion(pester)[0] !== 5) problems.push(`Pester must be 5.x (the tests use Pester 5 syntax), got ${pester}`);
  return { ok: problems.length === 0, problems };
}

// node claude-version.mjs check --claude 2.1.322 --powershell 7.5.4 --pester 5.7.1
// node claude-version.mjs decide --current 2.1.322 [--min-age-days 3] [--rejected 2.1.400,2.1.401] [--allow-major]
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/\\/g, '/').split('/').pop())) {
  try {
    const [command, ...rest] = process.argv.slice(2), arg = name => { const i = rest.indexOf(name); return i >= 0 ? rest[i + 1] : undefined; };
    if (command === 'check') {
      const result = checkPins({ claude: arg('--claude'), powershell: arg('--powershell'), pester: arg('--pester') });
      for (const problem of result.problems) console.error(problem);
      process.exitCode = result.ok ? 0 : 1;
    } else if (command === 'decide') {
      const result = chooseVersion({ current: arg('--current'), registry: await fetchRegistry(), minAgeDays: Number(arg('--min-age-days') ?? 3),
        rejected: (arg('--rejected') ?? '').split(',').filter(Boolean), allowMajor: rest.includes('--allow-major') });
      console.log(JSON.stringify(result));
    } else throw new Error('Usage: check --claude <x.y.z> --powershell <x.y.z> --pester <x.y.z> | decide --current <x.y.z> [--min-age-days n] [--rejected a,b] [--allow-major]');
  } catch (error) { console.log(JSON.stringify({ action: 'error', reason: String(error.message ?? error) })); process.exitCode = 1; }
}
