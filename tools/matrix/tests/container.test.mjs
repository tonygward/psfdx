import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { checkPins, chooseVersion, compareVersions, parseVersion } from '../../matrix-linux/claude-version.mjs';
import { validateConfig } from '../config.mjs';
import { inCoreScope } from '../../../scripts/matrix/automerge.mjs';
import { EXIT } from '../local-tests.mjs';

const dir = new URL('../../matrix-linux/', import.meta.url);
const read = name => fs.readFileSync(new URL(name, dir), 'utf8');
const files = ['Dockerfile', 'entrypoint.sh', 'verify-isolation.sh', 'test-broker.sh', 'sandbox-probe.sh', 'run-tests-sandboxed', 'Start-MatrixPsfdx.ps1', 'squid/squid.conf', 'worker.config.json', 'versions.json', 'README.md', 'claude-version.mjs'];

test('every file is there, and none (except the README, which explains the separation) mentions the other worker', () => {
  for (const name of files) {
    assert.ok(fs.existsSync(new URL(name, dir)), name);
    if (name !== 'README.md') assert.doesNotMatch(read(name), /songsmith|audio-plugins/i, name);
  }
});

test('shell scripts are checked out with Unix line endings, and parse', () => {
  assert.match(read('.gitattributes'), /^\* text eol=lf$/m);
  for (const name of ['entrypoint.sh', 'verify-isolation.sh', 'test-broker.sh', 'sandbox-probe.sh', 'run-tests-sandboxed']) {
    assert.doesNotMatch(read(name), /\r/, `${name} has carriage returns`);
    assert.match(read(name), /^#!\/bin\/sh\n/, name);
    const sh = spawnSync('sh', ['-n', new URL(name, dir).pathname.replace(/^\/([A-Za-z]:)/, '$1')], { encoding: 'utf8' });
    if (sh.error) continue; // no POSIX shell on this machine: the container build is the real check
    assert.equal(sh.status, 0, `${name}: ${sh.stderr}`);
  }
});

test('names are all psfdx-matrix- and nothing is shared with another worker', () => {
  const script = read('Start-MatrixPsfdx.ps1');
  for (const name of ["'psfdx-matrix-agent:dev'", "'psfdx-matrix-internal'", "'psfdx-matrix-egress'", "'psfdx-matrix-agent'", "'psfdx-matrix-home'", "'psfdx-matrix-work'"]) assert.ok(script.includes(name), name);
  assert.doesNotMatch(script, /(?<!psfdx-)matrix-(?:agent|egress|work|home|internal)\b/);
  assert.doesNotMatch(script, /agent-internal/);
  assert.match(script, /ValidateSet\('Build', 'Verify', 'Login', 'Run', 'Ensure', 'Logs', 'Pause', 'Resume', 'Stop', 'Down'\)/);
});

test('the image has PowerShell 7 and Pester 5 pinned, no sudo or Docker CLI, no set-id programs, and bakes the worker in', () => {
  const docker = read('Dockerfile');
  assert.match(docker, /FROM \$\{NODE_IMAGE\}/); assert.match(docker, /NODE_IMAGE=node:24-/);
  assert.match(docker, /ARG POWERSHELL_VERSION/); assert.match(docker, /ARG PESTER_VERSION/); assert.match(docker, /ARG CLAUDE_CODE_VERSION/);
  assert.match(docker, /Install-Module Pester -RequiredVersion '\$\{PESTER_VERSION\}'/);
  assert.match(docker, /-perm \/6000 -type f -exec chmod a-s/);
  assert.doesNotMatch(docker, /apt-get install[^\n]*\b(sudo|docker)/);
  assert.match(docker, /COPY --chown=root:root tools\/matrix\/\*\.mjs \/opt\/matrix\/tools\/matrix\//);
  assert.match(docker, /groupadd --gid 10002 matrix-test/);
  assert.match(docker, /chmod 0700 \/opt\/host-secrets/);
  assert.ok(!/VOLUME|--mount|-v /.test(docker), 'nothing is mounted from the host by the image');
});

test('the pins are exact, accepted by the version check, and match the usage gate', () => {
  const pins = JSON.parse(read('versions.json'));
  assert.deepEqual(checkPins({ claude: pins.claudeCode, powershell: pins.powershell, pester: pins.pester }), { ok: true, problems: [] });
  assert.deepEqual(Object.keys(pins).sort(), ['claudeCode', 'pester', 'powershell']);
});

test('the version check rejects loose, wrong-family and wrong-major pins', () => {
  assert.equal(checkPins({ claude: '2.1.318', powershell: '7.5.4', pester: '5.7.1' }).ok, false);
  assert.equal(checkPins({ claude: '2.2.0', powershell: '7.5.4', pester: '5.7.1' }).ok, false);
  assert.equal(checkPins({ claude: '2.1.322', powershell: '7.5', pester: '5.7.1' }).problems[0], 'PowerShell must be an exact stable x.y.z version, got "7.5"');
  assert.match(checkPins({ claude: '2.1.322', powershell: '6.2.7', pester: '5.7.1' }).problems[0], /PowerShell must be 7\.x/);
  assert.match(checkPins({ claude: '2.1.322', powershell: '7.5.4', pester: '6.0.0' }).problems[0], /Pester must be 5\.x/);
  assert.deepEqual(checkPins({ claude: 'latest', powershell: undefined, pester: '' }).problems.length, 3);
});

test('the egress allow-list names exactly the hosts the policy allows and refuses private ranges', () => {
  const squid = read('squid/squid.conf');
  const hosts = [...squid.matchAll(/^acl allowed_hosts dstdomain (.+)$/gm)].flatMap(m => m[1].trim().split(/\s+/)).sort();
  assert.deepEqual(hosts, ['.anthropic.com', '.claude.ai', '.claude.com', 'api.github.com', 'codeload.github.com', 'github.com', 'objects.githubusercontent.com'].sort());
  assert.match(squid, /http_access deny private_dst/);
  assert.match(squid, /http_access allow agent_net authed CONNECT ssl_ports allowed_hosts\r?\nhttp_access deny all/);
  assert.match(squid, /auth_param basic program \/usr\/lib\/squid\/basic_ncsa_auth \/etc\/squid\/passwd/);
  assert.match(squid, /acl authed proxy_auth REQUIRED/);
  // Squid refuses a host listed beside a parent domain, so no entry may be a subdomain of another.
  for (const a of hosts) for (const b of hosts) if (a !== b && b.startsWith('.') && a.endsWith(b)) assert.fail(a + ' is redundant next to ' + b);
  assert.match(squid, /acl ssl_ports port 443/);
  assert.doesNotMatch(squid, /powershellgallery|npmjs/);
});

test('the shipped worker.config.json is valid, states dry run explicitly, and points at the baked-in paths', () => {
  const config = JSON.parse(read('worker.config.json'));
  assert.doesNotThrow(() => validateConfig(config));
  assert.equal(config.boardPickup.enabled, true); assert.equal(typeof config.boardPickup.dryRun, 'boolean');
  assert.equal(config.worker.testRunner, '/opt/matrix/run-tests-sandboxed');
  assert.equal(config.repositorySlug, 'tonygward/psfdx'); assert.equal(config.delivery.psGallery.enabled, false);
  for (const path of [config.worker.tokenFile, config.boardPickup.tokenFile]) assert.match(path, /^\/run\/matrix-secrets\//);
  assert.doesNotMatch(JSON.stringify(config), /RELEASE_TOKEN|ANTHROPIC_API_KEY/);
});

test('the entrypoint drops privileges, reads only the two secrets, and never mounts or prints them', () => {
  const entry = read('entrypoint.sh');
  assert.match(entry, /setpriv --reuid=10001 --regid=10001 --clear-groups --bounding-set=-all --inh-caps=-all --no-new-privs/);
  assert.match(entry, /for name in agent_github_token board_token/);
  assert.doesNotMatch(entry, /RELEASE|PUBLISH|ANTHROPIC_API_KEY/);
  assert.match(entry, /node \/opt\/matrix\/tools\/matrix\/worker\.mjs/); assert.match(entry, /sleep 300/);
  assert.match(entry, /clone --no-tags https:\/\/github\.com\/tonygward\/psfdx\.git/);
});

test('the broker only runs a fixed command, validates every field, and fails closed without a network namespace', () => {
  const broker = read('test-broker.sh');
  assert.match(broker, /\(PSF\|AUTO\)-\[0-9\]\+\/repo\$/);
  assert.match(broker, /\[ "\$results" = "\$task\/testResults\.xml" \]/);
  assert.match(broker, /\[ "\$seconds" -ge 30 \] && \[ "\$seconds" -le 3600 \]/);
  assert.match(broker, /\[ "\$NETNS" = none \] && \{[^}]*reply "\$id" 125/);
  assert.match(broker, /chown -R --no-dereference/);
  assert.match(broker, /Import-Module Pester -MinimumVersion 5\.0\.0 -MaximumVersion 5\.99\.99/);
  assert.match(broker, /--bounding-set=-all --inh-caps=-all --no-new-privs/);
  assert.match(broker, /unshare --user --map-current-user --net --pid --fork --kill-child/);
  assert.doesNotMatch(broker, /\beval\b/);
  // The broker's exit codes are the ones the worker's sandbox adapter expects.
  assert.deepEqual(EXIT, { passed: 0, failed: 1, timeout: 124, refused: 125 });
  const wrapper = read('run-tests-sandboxed');
  assert.match(wrapper, /Exit codes: 0 tests passed, 1 tests failed, 124 timed out, 125 the sandbox refused/);
  assert.match(wrapper, /ignored on purpose/);
});

test('the self-test covers every reference check plus the test sandbox', () => {
  const verify = read('verify-isolation.sh');
  for (const phrase of ['runs as a non-root user', 'no Docker socket', 'no Docker CLI', 'no sudo', 'cannot write to the root file system', 'no effective capabilities', 'no-new-privileges',
    'no set-id programs', 'no release, publishing or API-key credentials', 'direct internet access blocked', 'home network not reachable', 'proxy refuses', 'proxy allows', 'claude CLI runs',
    'PowerShell', 'Pester', 'the raw secrets mount is closed to the agent', 'ALL CHECKS PASSED', 'SOME CHECKS FAILED']) assert.ok(verify.includes(phrase), phrase);
  const probe = read('sandbox-probe.sh');
  for (const phrase of ['cannot read $path', 'cannot read another worktree', 'cannot write $path', 'can write its worktree', 'no proxy variables', 'cannot reach the egress proxy', 'cannot reach the internet', 'no network device except loopback']) assert.ok(probe.includes(phrase), phrase);
  assert.match(probe, /\/run\/matrix-secrets\/agent_github_token/); assert.match(probe, /\/work\/state/);
  assert.match(verify, /\[ "\$fail" = 0 \] && echo "ALL CHECKS PASSED"/);
});

test('the gate keeps everything in matrix-linux outside the core lane except the config and the README', () => {
  assert.ok(inCoreScope('tools/matrix-linux/worker.config.json'));
  assert.ok(inCoreScope('tools/matrix-linux/README.md'));
  for (const name of ['Dockerfile', 'entrypoint.sh', 'verify-isolation.sh', 'test-broker.sh', 'sandbox-probe.sh', 'run-tests-sandboxed', 'Start-MatrixPsfdx.ps1', 'squid/squid.conf', 'versions.json', 'claude-version.mjs']) {
    assert.equal(inCoreScope(`tools/matrix-linux/${name}`), false, name);
  }
});

// Claude Code version choice (ported from the reference)
const DAY = 86400000, now = Date.parse('2026-11-12T12:00:00Z');
const ago = days => new Date(now - days * DAY).toISOString();
const registry = (entries, latest) => ({
  name: '@anthropic-ai/claude-code',
  'dist-tags': { latest: latest ?? entries.filter(e => parseVersion(e[0])).at(-1)[0] },
  versions: Object.fromEntries(entries.map(([v, , extra]) => [v, extra ?? {}])),
  time: Object.fromEntries(entries.map(([v, days]) => [v, ago(days)])),
});
const choose = (reg, extra = {}) => chooseVersion({ current: '2.1.322', registry: reg, now, ...extra });

test('versions compare numerically and only stable x.y.z counts', () => {
  assert.equal(compareVersions('2.1.10', '2.1.9'), 1); assert.equal(compareVersions('2.0.0', '2.0.0'), 0); assert.equal(compareVersions('1.9.9', '2.0.0'), -1);
  assert.equal(parseVersion('2.1.3-beta.1'), null); assert.equal(parseVersion('latest'), null); assert.equal(parseVersion(undefined), null);
  assert.throws(() => compareVersions('2.1.3-beta', '2.1.2'));
});

test('takes the newest version that is old enough', () => {
  const r = choose(registry([['2.1.322', 30], ['2.1.330', 10], ['2.1.340', 5], ['2.1.350', 1]]));
  assert.equal(r.action, 'update'); assert.equal(r.target, '2.1.340');
});

test('a version younger than the minimum age waits, and says when it becomes eligible', () => {
  const r = choose(registry([['2.1.322', 30], ['2.1.330', 1]]));
  assert.equal(r.action, 'none'); assert.match(r.reason, /2\.1\.330 is newer but younger than 3 days; eligible from 2026-11-14/);
  assert.equal(choose(registry([['2.1.322', 30], ['2.1.330', 1]]), { minAgeDays: 0 }).target, '2.1.330');
});

test('never downgrades, never reinstalls the current version', () => {
  assert.equal(choose(registry([['2.1.300', 40], ['2.1.322', 30]])).action, 'none');
  assert.match(choose(registry([['2.1.322', 30]])).reason, /newest eligible/);
});

test('skips deprecated versions, rejected versions and pre-releases', () => {
  const r = registry([['2.1.322', 30], ['2.1.330', 10], ['2.1.340', 9, { deprecated: 'broken' }], ['2.1.350-beta.1', 8], ['2.1.360', 7]]);
  assert.equal(choose(r, { rejected: ['2.1.360'] }).target, '2.1.330');
  assert.equal(choose(r).target, '2.1.360');
});

test('a new major version needs an explicit flag', () => {
  const r = registry([['2.1.322', 30], ['3.0.0', 20]]);
  assert.equal(choose(r).action, 'none'); assert.equal(choose(r, { allowMajor: true }).target, '3.0.0');
});

test('never newer than the latest tag, never trusts a version with no publish time', () => {
  const r = registry([['2.1.322', 30], ['2.1.330', 10], ['2.1.340', 9]], '2.1.330');
  assert.equal(choose(r).target, '2.1.330');
  const noTime = registry([['2.1.322', 30], ['2.1.330', 10]]); delete noTime.time['2.1.330'];
  assert.equal(choose(noTime).action, 'none');
});

test('a registry with no stable latest, or a bad current version, never updates', () => {
  assert.equal(choose({ 'dist-tags': {}, versions: {}, time: {} }).action, 'none');
  assert.throws(() => choose(registry([['2.1.330', 10]]), { current: 'next' }));
});

test('without a network namespace the broker only runs tests if the proxy demands a credential, and kills stray processes', () => {
  const broker = read('test-broker.sh');
  assert.match(broker, /elif proxy_demands_auth; then echo proxyauth/);
  assert.match(broker, /\[ "\$status" = 407 \]/);
  assert.match(broker, /pkill -KILL -u "\$TEST_UID"/);
  assert.match(read('Dockerfile'), /util-linux procps/);
  const launcher = read('Start-MatrixPsfdx.ps1');
  assert.match(launcher, /function Get-ProxyCredential/);
  assert.match(launcher, /'proxy\.passwd'\):\/etc\/squid\/passwd:ro/);
  assert.match(launcher, /HTTPS_PROXY=http:\/\/matrix:\$\{proxyPassword\}@/);
  assert.ok(!/proxy-password/.test(read('worker.config.json')), 'the credential never goes in the config');
  assert.match(read('sandbox-probe.sh'), /the proxy refuses the test user without the credential \(407\)/);
});
