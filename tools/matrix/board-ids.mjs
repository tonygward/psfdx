// Run once by the owner with the board token to print the IDs that `boardPickup` needs.
//   node tools/matrix/board-ids.mjs <owner> <project number>
// Uses `gh` (which reads GH_TOKEN) and prints JSON to paste into worker.json. Prints no token.
import { spawnSync } from 'node:child_process';

export const IDS_QUERY = `query($owner: String!, $number: Int!) {
  user(login: $owner) { projectV2(number: $number) { id title fields(first: 50) { nodes { ... on ProjectV2SingleSelectField { id name options { id name } } } } } }
}`;
export const STATUS_NAMES = ['Backlog', 'Todo', 'Doing', 'Blocked', 'Done'];

export function extractIds(response) {
  const project = response?.data?.user?.projectV2;
  if (!project) throw new Error('Project not found. Check the owner, the number and that the token can read it');
  const status = (project.fields?.nodes ?? []).find(field => field?.name === 'Status');
  if (!status) throw new Error('The project has no single-select field named Status');
  const options = {};
  for (const name of STATUS_NAMES) {
    const option = status.options.find(o => o.name === name);
    if (!option) throw new Error(`The Status field has no option named ${name}`);
    options[name.toLowerCase()] = option.id;
  }
  return { projectId: project.id, statusFieldId: status.id, options };
}

export function fetchIds(owner, number, { run = spawnSync } = {}) {
  const result = run('gh', ['api', 'graphql', '-f', `query=${IDS_QUERY}`, '-f', `owner=${owner}`, '-F', `number=${number}`], { encoding: 'utf8', shell: false, windowsHide: true });
  if (result.error || result.status !== 0) throw new Error('gh could not read the project. Check GH_TOKEN and its Projects permission');
  return extractIds(JSON.parse(result.stdout));
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1].startsWith('/') ? '' : '/'}${process.argv[1].replaceAll('\\', '/')}`).href) {
  const [owner, number] = process.argv.slice(2);
  if (!owner || !/^\d+$/.test(number ?? '')) { console.error('Usage: node tools/matrix/board-ids.mjs <owner> <project number>'); process.exit(2); }
  try { console.log(JSON.stringify(fetchIds(owner, Number(number)), null, 2)); }
  catch (error) { console.error(error.message); process.exit(1); }
}
