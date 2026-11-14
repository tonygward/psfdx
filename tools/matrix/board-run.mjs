// One board-driven tick, composed from board.mjs, doing.mjs, pickup.mjs, issue-prompt.mjs and handoff.mjs.
// Nothing here starts Claude. Off unless config.boardPickup.enabled is true. dryRun defaults to true: decide and report,
// never claim, comment, move a card or change the saved state.
import path from 'node:path';
import { atomic, locked, readState } from './state.mjs';
import { fetchBoard, fetchPulls, selectFromBoard, pullTaskState, matrixBranchTask } from './board.mjs';
import { reconcileDoing } from './doing.mjs';
import { scan, readPromptFiles } from './backlog.mjs';
import { pickUp, recoverPickupComments } from './pickup.mjs';
import { writeHandoff, clearHandoff } from './handoff.mjs';
import { resolveFromIssues } from './issue-prompt.mjs';
import { dailyDue, londonDay, DAILY_TIME } from './policy.mjs';

// A board tick must keep an active claim intact: it only adds or refreshes tasks that are still unclaimed.
// The board column decides what runs; wording in a prompt never does.
export function refreshTasks(state, prompts, revision, now = new Date().toISOString()) {
  for (const p of prompts) {
    const task = state.tasks[p.id] ??= { id: p.id, state: 'pending', attempts: 0, created: now };
    if (p.complete && ['pending', 'withdrawn'].includes(task.state)) task.state = 'complete';
    else if (task.state === 'withdrawn') task.state = 'pending';
    if (['pending', 'withdrawn', 'complete'].includes(task.state)) Object.assign(task, { file: p.file, hash: p.hash, revision, updated: now });
  }
}

// A claimed task whose Matrix pull request has merged enters the delivery lifecycle (AUTO-08 plugs in through housekeeping).
export function syncMerges(state, pulls, prefixes) {
  const recorded = [];
  for (const task of Object.values(state.tasks)) {
    if (!task.job || !task.itemId || state.deliveries?.[task.id]) continue;
    const pull = pulls.find(p => p.state === 'MERGED' && matrixBranchTask(p, prefixes) === task.id);
    if (pull) { (state.mergedPulls ??= {})[task.id] = { repository: pull.repository, pull: pull.number }; recorded.push(task.id); }
  }
  return recorded;
}

/**
 * deps: { graphql, io, loadUsage(config), loadPrompts(), jobId, clock, handoff, limits, housekeeping[] }
 * housekeeping: async functions run first, each given { dir, board, pulls, io }. Later prompts add the delivery and
 * blocked-card steps here.
 */
export async function boardTick(config, deps) {
  const settings = config.boardPickup;
  if (settings?.enabled !== true) return { ran: false, reason: 'Board pickup is not enabled' };
  const { graphql, io, loadUsage, loadPrompts, jobId, clock = Date.now, handoff = false, limits = null, housekeeping = [] } = deps;
  const dir = config.stateDirectory, dryRun = settings.dryRun !== false, prefixes = config.idPrefixes;
  const repository = settings.repository ?? config.repositorySlug, ownerLogin = settings.ownerLogin ?? null;
  const stop = (reason, extra = {}) => ({ ran: true, dryRun, selected: null, blocker: reason, ...extra });

  if (handoff && !dryRun) clearHandoff(dir); // a hand-off only ever comes from this tick
  const board = await fetchBoard(graphql, settings.projectId, { clock, prefixes });
  if (!board.ok) return stop(board.reason);
  const pulled = await fetchPulls(graphql, repository);
  if (!pulled.ok) return stop(pulled.reason);

  // A broken prompt file must not stop work that has already merged: housekeeping runs first, then nothing new is picked.
  let prompts = [], revision = null, promptBlock = null;
  try {
    const loaded = await loadPrompts();
    revision = loaded.revision;
    const scanned = scan(loaded.files, { prefixes, promptDirectory: config.promptDirectory });
    if (scanned.errors.length > 0) promptBlock = `Prompt scan has ${scanned.errors.length} error(s): ${scanned.errors.map(e => `${e.file}: ${e.reason}`).join('; ')}`;
    else prompts = scanned.prompts;
  } catch (error) { promptBlock = `Prompts could not be read: ${error.message}`; }

  const { merged, open } = pullTaskState(pulled.pulls, prefixes);
  const early = readState(dir, { restart: false });
  const todoDue = dailyDue(early.lastWorkerDaily, config.dailyTime ?? DAILY_TIME, new Date(clock()));
  const statuses = todoDue ? ['Doing', 'Todo'] : ['Doing'];

  // A card with no prompt file can still be built when its issue has enough detail. Dry runs assess and write nothing.
  let issuePrompts = { prompts: [], blocked: [], notes: [] };
  if (!promptBlock && io.issueBody) {
    issuePrompts = await resolveFromIssues({ board, prompts, tasks: early.tasks, io, statuses, repository, ownerLogin, prefixes, dryRun, merged, open });
    prompts = [...prompts, ...issuePrompts.prompts];
  }

  // Keep saved state in step with the repository and with merged pull requests (needs the lock).
  const recordedMerges = dryRun ? [] : await locked(dir, async () => {
    const state = readState(dir, { restart: false });
    if (!promptBlock) refreshTasks(state, prompts, revision);
    const recorded = syncMerges(state, pulled.pulls, prefixes);
    atomic(path.join(dir, 'state.json'), state);
    return recorded;
  });
  let state = readState(dir, { restart: false });

  // Resume anything half-way before considering new work: a lost starting comment, then later steps.
  if (!dryRun) {
    if (!promptBlock) await recoverPickupComments(dir, { revision, io, limits });
    for (const step of housekeeping) await step({ dir, board, pulls: pulled.pulls, io, clock });
    state = readState(dir, { restart: false });
  }

  const common = { notes: issuePrompts.notes, recordedMerges };
  if (promptBlock) return stop(`Nothing new is picked up: ${promptBlock}`, common);
  const doing = reconcileDoing(board, prompts, pulled.pulls, state.tasks, prefixes);
  if (!doing.enableAllowed) return stop('Doing cards disagree with pull requests or worker state', { doing, ...common });

  const usage = loadUsage(config.claudeUsage);
  if (!usage.allowed || usage.extraUsageEnabled !== false) return stop(usage.reason ?? 'Usage not verified', { doing, ...common });
  const active = Object.values(state.tasks).find(task => task.state === 'claimed');
  const result = selectFromBoard(board, prompts, {
    now: clock(), statuses, usage: usage.snapshot, scopedUsagePercent: usage.meters?.filter(m => m.kind === 'weekly_scoped').map(m => m.percentage) ?? [],
    tasks: state.tasks, activeJob: active ? active.job ?? active.id : null, mergedTaskIds: merged, openPullTaskIds: open, repository, ownerLogin,
  });
  if (!result.selected) return stop(result.blocker, { decisions: result.decisions, doing, ...common });
  if (dryRun) return { ran: true, dryRun, selected: result.selected, decisions: result.decisions, doing, ...common };
  if (handoff) {
    writeHandoff(dir, { selected: result.selected, job: jobId, revision, now: clock(), resumedFrom: state.tasks[result.selected.taskId]?.resumedFrom ?? null });
    return { ran: true, dryRun, handoff: true, selected: result.selected, decisions: result.decisions, doing, ...common };
  }
  const claimed = await pickUp(dir, result.selected, { job: jobId, revision, io, limits });
  if (claimed.claimed && result.selected.status === 'Todo') {
    await locked(dir, async () => { const s = readState(dir, { restart: false }); s.lastWorkerDaily = londonDay(new Date(clock())); atomic(path.join(dir, 'state.json'), s); });
  }
  return { ran: true, dryRun, selected: claimed.claimed ? result.selected : null, claim: claimed, decisions: result.decisions, doing, ...common };
}

// Adapters for a real run. `gh` returns stdout; `git` returns stdout from the source checkout.
export function ghGraphql(gh) {
  return async (query, variables) => {
    const args = ['api', 'graphql', '-f', `query=${query}`];
    for (const [key, value] of Object.entries(variables)) {
      if (value === null || value === undefined) continue;
      if (Array.isArray(value)) for (const item of value) args.push('-f', `${key}[]=${item}`);
      else args.push(typeof value === 'string' ? '-f' : '-F', `${key}=${value}`);
    }
    return JSON.parse(await gh(args));
  };
}

// Fetches the base branch, then reads prompts from that exact revision (never from the working tree).
export const promptLoader = (config, options = {}) => async () => readPromptFiles({
  cwd: config.sourceDirectory, promptDirectory: config.promptDirectory, ref: `refs/remotes/origin/${config.baseBranch}`, fetchBranch: config.baseBranch, ...options });
