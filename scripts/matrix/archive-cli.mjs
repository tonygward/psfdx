// Moves the prompt for a merged task into prompts/done/.
// Usage: node scripts/matrix/archive-cli.mjs <matrix branch | task ID>
// Run from a checkout of main, after the merge. Prints the moved path; exits 3 when there is nothing to do.
import fs from 'node:fs';
import path from 'node:path';
import { archivePath, markDone, promptIdFromBranch, relinkMoved } from './automerge.mjs';

const arg = process.argv[2] ?? '';
const id = /^(?:PSF|AUTO)-\d+$/.test(arg) ? arg : promptIdFromBranch(arg);
if (!id) { console.error('Not a Matrix branch or task ID'); process.exit(2); }

const source = fs.existsSync('prompts')
  ? fs.readdirSync('prompts').find(name => name.startsWith(`${id}-`) && name.endsWith('.md'))
  : undefined;
const from = source && `prompts/${source}`;
const target = from && archivePath(from);
if (!target) { console.log(`Nothing to archive for ${id}`); process.exit(3); }

fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, markDone(fs.readFileSync(from, 'utf8'), from, target));
fs.rmSync(from);
console.log(`${from} -> ${target}`);

// Repair links to the moved prompt in every other Markdown page (README indexes, other prompts, docs).
const repaired = [];
const pages = directory => {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) { if (!['node_modules', '.git'].includes(entry.name)) pages(full); }
    else if (entry.name.endsWith('.md')) {
      const file = path.relative('.', full).split(path.sep).join('/');
      if (file === target) continue;
      const before = fs.readFileSync(full, 'utf8');
      const after = relinkMoved(before, file, from, target);
      if (after !== before) { fs.writeFileSync(full, after); repaired.push(file); }
    }
  }
};
pages('.');
if (repaired.length) console.log(`Links updated in: ${repaired.join(', ')}`);
