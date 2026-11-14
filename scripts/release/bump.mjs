// Usage: node scripts/release/bump.mjs [--date YYYY-MM-DD]
// Bumps VERSION, every manifest and CHANGELOG.md. Prints the new version.
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import {
  parseVersion, bumpPatch, assertInStep, writeManifestVersion, moveUnreleased,
} from './bump-lib.mjs';

const root = process.cwd();
const dateArg = process.argv.indexOf('--date');
const date = dateArg > -1 ? process.argv[dateArg + 1] : new Date().toISOString().slice(0, 10);

const versionText = readFileSync(join(root, 'VERSION'), 'utf8');
const current = parseVersion(versionText);
const manifests = readdirSync(root, { withFileTypes: true })
  .filter((d) => d.isDirectory() && d.name.startsWith('psfdx'))
  .map((d) => join(root, d.name, `${d.name}.psd1`))
  .filter((p) => existsSync(p))
  .map((p) => ({ name: p, text: readFileSync(p, 'utf8') }));

assertInStep(current, manifests);
const next = bumpPatch(current);

writeFileSync(join(root, 'VERSION'), next + (versionText.includes('\r\n') ? '\r\n' : '\n'));
for (const m of manifests) writeFileSync(m.name, writeManifestVersion(m.text, next));
const changelogPath = join(root, 'CHANGELOG.md');
writeFileSync(changelogPath, moveUnreleased(readFileSync(changelogPath, 'utf8'), next, date));
console.log(next);
