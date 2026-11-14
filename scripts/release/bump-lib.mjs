// Pure logic for the version bump. No file or Git access here.

export function parseVersion(text) {
  const value = String(text).trim();
  if (!/^\d+\.\d+\.\d+$/.test(value)) {
    throw new Error(`VERSION must be three numeric parts, got "${value}"`);
  }
  return value;
}

export function bumpPatch(version) {
  const [major, minor, patch] = parseVersion(version).split('.').map(Number);
  return `${major}.${minor}.${patch + 1}`;
}

const MODULE_VERSION = /^(\s*ModuleVersion\s*=\s*)'([^']*)'/m;

export function readManifestVersion(manifestText) {
  const match = MODULE_VERSION.exec(manifestText);
  return match ? match[2] : null;
}

export function writeManifestVersion(manifestText, version) {
  if (!MODULE_VERSION.test(manifestText)) {
    throw new Error('No ModuleVersion line found in manifest');
  }
  return manifestText.replace(MODULE_VERSION, `$1'${version}'`);
}

// manifests: [{ name, text }]. Throws if any disagree with the VERSION file.
export function assertInStep(version, manifests) {
  const bad = manifests
    .map((m) => ({ name: m.name, found: readManifestVersion(m.text) }))
    .filter((m) => m.found !== version);
  if (bad.length > 0) {
    const detail = bad.map((m) => `${m.name} has ${m.found}`).join(', ');
    throw new Error(`VERSION is ${version} but ${detail}`);
  }
}

// Moves everything under "## Unreleased" into "## X.Y.Z - date".
export function moveUnreleased(changelogText, version, date) {
  const eol = changelogText.includes('\r\n') ? '\r\n' : '\n';
  const lines = changelogText.split(/\r?\n/);
  const start = lines.findIndex((l) => l.trim() === '## Unreleased');
  if (start === -1) throw new Error('CHANGELOG.md has no "## Unreleased" section');
  let end = lines.findIndex((l, i) => i > start && /^## /.test(l));
  if (end === -1) end = lines.length;
  let body = lines.slice(start + 1, end);
  while (body.length > 0 && body[0].trim() === '') body.shift();
  while (body.length > 0 && body[body.length - 1].trim() === '') body.pop();
  if (body.length === 0) body = ['- Maintenance release.'];
  const out = [
    ...lines.slice(0, start + 1),
    '',
    `## ${version} - ${date}`,
    '',
    ...body,
    '',
    ...lines.slice(end),
  ];
  return out.join(eol);
}

// Returns the notes for one version, or null.
export function sectionFor(changelogText, version) {
  const lines = changelogText.split(/\r?\n/);
  const start = lines.findIndex((l) => l.startsWith(`## ${version} `) || l.trim() === `## ${version}`);
  if (start === -1) return null;
  let end = lines.findIndex((l, i) => i > start && /^## /.test(l));
  if (end === -1) end = lines.length;
  return lines.slice(start + 1, end).join('\n').trim();
}

// Files and folders that go in the release zip, from the module list.
export function zipEntries(modules) {
  return [
    ...modules,
    'install.ps1',
    'install-windows.ps1',
    'uninstall.ps1',
    'uninstall-windows.ps1',
    'modules.ps1',
    'README.md',
    'CHANGELOG.md',
  ];
}
