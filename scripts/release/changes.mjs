// The one place that decides which changed files matter. Used by:
//   - CI - Pester tests          (`tests`: does this change need the Pester suite?)
//   - CD - Bump version          (`ships`: does this change alter what users install?)
//   - tools/matrix/verifiers.mjs (delivery check: was a release expected?)
//
// Usage: git diff --name-only A B | node scripts/release/changes.mjs tests|ships   (prints true or false)
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// Product: what a user installs. Anything else in the repository is infrastructure and never causes a release.
const SHIPS = [
  /^psfdx[^/]*\//,
  /^modules\.ps1$/,
  /^(?:un)?install(?:-windows)?\.ps1$/,
  /^VERSION$/,
  // The script that assembles the Gallery package decides what is in it, so a change to it changes what users install.
  /^scripts\/release\/Build-GalleryPackage\.ps1$/,
];
// Inside a module folder, tests and Markdown do not ship.
const SHIPS_NOT = [/\.Tests\.ps1$/, /\.md$/];

export const shipsRelease = file => SHIPS.some(p => p.test(file)) && !SHIPS_NOT.some(p => p.test(file));

// A change that ships nothing has nothing to release. An empty list is not "ships nothing" (something is wrong).
export const shipsNothing = files => Array.isArray(files) && files.length > 0 && !files.some(shipsRelease);

// Files the Pester suite cannot be affected by: documentation, prompts, images, and Matrix's own Node code and
// container files, which have their own test workflows. The Matrix launcher script is tested by Pester, so it is not exempt.
const NO_PESTER = [/\.md$/, /^prompts\//, /^docs\//, /^images\//, /\.(?:png|jpe?g|gif|svg)$/];
const PESTER_ANYWAY = [/^tools\/matrix-linux\/.*\.ps1$/];
const NO_PESTER_TOOLS = [/^tools\//];

export const needsPester = file => {
  if (PESTER_ANYWAY.some(p => p.test(file))) return true;
  return !NO_PESTER.concat(NO_PESTER_TOOLS).some(p => p.test(file));
};
export const testsNeeded = files => Array.isArray(files) && files.some(needsPester);

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const files = readFileSync(0, 'utf8').split(/\r?\n/).map(f => f.trim()).filter(Boolean);
  const mode = process.argv[2];
  if (mode === 'ships') console.log(String(!shipsNothing(files) && files.length > 0));
  else if (mode === 'tests') console.log(String(testsNeeded(files)));
  else { console.error('Usage: changes.mjs tests|ships (file names on stdin)'); process.exit(2); }
}
