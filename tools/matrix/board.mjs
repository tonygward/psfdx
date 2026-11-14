// Board-ordered pickup. Pure decision logic plus a read-only board fetcher: nothing here claims, comments or writes.
// Ordering comes only from the project's POSITION order (the visible manual drag order of the single table view).
// Never from prompt priority, task ID or issue number.
import { usageGate, WEEKLY_LIMIT_PERCENT } from './policy.mjs';

export const BOARD_STALE_MS = 60000;
export const MAX_PAGES = 20;
export const EXPECTED_VIEW_COUNT = 1; // POSITION order was verified with drags in one view only.
export const DEFAULT_PREFIXES = ['PSF', 'AUTO'];

const taskPattern = prefixes => new RegExp(`^((?:${prefixes.join('|')})-\\d{2,})\\b`);

export const BOARD_QUERY = `query($id: ID!, $after: String) {
  node(id: $id) { ... on ProjectV2 {
    views(first: 10) { totalCount }
    items(first: 100, after: $after, orderBy: { field: POSITION, direction: ASC }) {
      totalCount pageInfo { hasNextPage endCursor }
      nodes {
        id
        status: fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
        content { __typename ... on Issue { number title state authorAssociation author { login } repository { nameWithOwner } } }
      }
    }
  } }
}`;

// Reads the whole board in POSITION order. Any API error, partial page set or unexpected view layout
// returns { ok: false } so the caller does no work. There is no fallback ordering.
export async function fetchBoard(graphql, projectId, { clock = Date.now, prefixes = DEFAULT_PREFIXES } = {}) {
  const cards = [];
  let after = null;
  try {
    for (let page = 0; page < MAX_PAGES; page++) {
      const project = (await graphql(BOARD_QUERY, { id: projectId, after }))?.data?.node;
      if (!project?.items) return { ok: false, reason: 'Board response missing items' };
      const views = project.views?.totalCount, total = project.items.totalCount;
      cards.push(...project.items.nodes);
      if (!project.items.pageInfo.hasNextPage) {
        if (views !== EXPECTED_VIEW_COUNT) return { ok: false, reason: `Board order verified for ${EXPECTED_VIEW_COUNT} view only; found ${views}` };
        if (cards.length !== total) return { ok: false, reason: 'Partial board snapshot' };
        return { ok: true, fetchedAt: new Date(clock()).toISOString(), cards: cards.map((node, index) => normaliseCard(node, index, prefixes)) };
      }
      after = project.items.pageInfo.endCursor;
      if (!after) return { ok: false, reason: 'Pagination cursor missing' };
    }
    return { ok: false, reason: 'Board exceeds page limit' };
  } catch (error) {
    return { ok: false, reason: `Board read failed: ${error.message}` };
  }
}

const PULLS_QUERY = `query($owner: String!, $name: String!, $states: [PullRequestState!], $after: String) {
  repository(owner: $owner, name: $name) { pullRequests(first: 100, after: $after, states: $states, orderBy: { field: UPDATED_AT, direction: DESC }) {
    pageInfo { hasNextPage endCursor } nodes { number state title headRefName }
  } }
}`;

// Pull requests that show a task is already being or has been implemented. Open ones are read completely.
// Merged ones are the most recent 100; the archived prompt (complete flag) is the backstop for anything older.
export async function fetchPulls(graphql, repository) {
  const pulls = [];
  try {
    const [owner, name] = repository.split('/');
    for (const states of [['OPEN'], ['MERGED']]) {
      let after = null;
      for (let page = 0; page < MAX_PAGES; page++) {
        const data = (await graphql(PULLS_QUERY, { owner, name, states, after }))?.data?.repository?.pullRequests;
        if (!data) return { ok: false, reason: `Pull request response missing for ${repository}` };
        pulls.push(...data.nodes.map(pull => ({ ...pull, repository })));
        if (!data.pageInfo.hasNextPage || states[0] === 'MERGED') break;
        after = data.pageInfo.endCursor;
        if (page === MAX_PAGES - 1) return { ok: false, reason: `Too many open pull requests in ${repository}` };
      }
    }
    return { ok: true, pulls };
  } catch (error) {
    return { ok: false, reason: `Pull request read failed: ${error.message}` };
  }
}

// Only Matrix implementation branches (matrix/<TASK-ID>[-slug]) count as an implementation. Archive branches,
// the core lane and pull requests that merely mention a task ID do not.
export function matrixBranchTask(pull, prefixes = DEFAULT_PREFIXES) {
  return new RegExp(`^matrix/((?:${prefixes.join('|')})-\\d{2,})(?:-[a-z0-9]+)*$`).exec(pull.headRefName ?? '')?.[1] ?? null;
}

export function pullTaskState(pulls, prefixes = DEFAULT_PREFIXES) {
  const merged = new Set(), open = new Set();
  for (const pull of pulls) {
    const branch = matrixBranchTask(pull, prefixes);
    if (pull.state === 'MERGED' && branch) merged.add(branch);
    if (pull.state === 'OPEN') { const id = branch ?? taskPattern(prefixes).exec(pull.title)?.[1]; if (id) open.add(id); }
  }
  return { merged, open };
}

// The board column is the only hold: Backlog and Blocked cards wait; Todo and Doing cards run.
// Wording inside an issue or prompt, such as "deferred", holds nothing.
export function normaliseCard(node, index, prefixes = DEFAULT_PREFIXES) {
  const issue = node.content?.__typename === 'Issue' ? node.content : null;
  return {
    position: index, itemId: node.id, status: node.status?.name ?? null, issue: issue?.number ?? null,
    state: issue?.state ?? null, repository: issue?.repository?.nameWithOwner ?? null,
    author: issue?.author?.login ?? null, authorAssociation: issue?.authorAssociation ?? null,
    taskId: issue ? taskPattern(prefixes).exec(issue.title)?.[1] ?? null : null, title: issue?.title ?? node.content?.title ?? '',
  };
}

// Public repository rule: only issues the repository owner wrote, in this repository.
export function ownerIssue(card, repository, ownerLogin) {
  return card.repository === repository && (card.authorAssociation === 'OWNER' || (!!ownerLogin && card.author === ownerLogin));
}

/**
 * Choose at most one card. Returns { selected, decisions, blocker }.
 * snapshot: result of fetchBoard (ok: true) | prompts: parsePrompt results from backlog.scan
 * context: { now, usage, scopedUsagePercent[], tasks, activeJob, mergedTaskIds, openPullTaskIds, statuses, repository, ownerLogin }
 */
export function selectFromBoard(snapshot, prompts, context) {
  const { now = Date.now(), usage, scopedUsagePercent = [], tasks = {}, activeJob = null, mergedTaskIds = new Set(), openPullTaskIds = new Set(),
    statuses = ['Doing', 'Todo'], repository, ownerLogin = null } = context;
  const stop = reason => ({ selected: null, decisions: [], blocker: reason });
  if (!snapshot?.ok) return stop(snapshot?.reason ?? 'No board snapshot');
  const age = now - Date.parse(snapshot.fetchedAt);
  if (!Number.isFinite(age) || age < 0 || age > BOARD_STALE_MS) return stop('Stale or invalid board snapshot');
  // Global gates stop the whole run. The queue is never walked down to bypass them.
  const gate = usageGate(usage, now);
  if (!gate.allowed) return stop(gate.reason);
  if (scopedUsagePercent.some(p => typeof p !== 'number' || !Number.isFinite(p) || p >= WEEKLY_LIMIT_PERCENT)) return stop(`Scoped weekly usage at or above ${WEEKLY_LIMIT_PERCENT}% or unknown`);
  if (activeJob) return stop(`Active job ${activeJob} must finish first (one active job)`);

  const byId = new Map(prompts.map(p => [p.id, p]));
  const complete = new Set(prompts.filter(p => p.complete).map(p => p.id));
  const activeIds = Object.values(tasks).filter(t => ['claimed', 'interrupted', 'awaiting-review'].includes(t.state)).map(t => t.id);
  // Only Doing and Todo run. Doing is a run-now request and is offered first; Todo is the ready queue. Each in board order.
  const queue = statuses.flatMap(status => snapshot.cards.filter(card => card.status === status));
  const decisions = [], seen = new Set();
  let selected = null;
  for (const card of queue) {
    const prompt = card.taskId ? byId.get(card.taskId) : null;
    const task = card.taskId ? tasks[card.taskId] : null;
    let reason = !card.issue ? 'not an issue card (pull request or draft)' : !card.taskId ? 'no task ID in issue title'
      : seen.has(card.taskId) ? 'duplicate card for task' : card.state !== 'OPEN' ? 'issue is closed'
      : !ownerIssue(card, repository, ownerLogin) ? 'issue was not written by the repository owner in this repository'
      : mergedTaskIds.has(card.taskId) || complete.has(card.taskId) ? 'implementation merged; delivery pending, do not recode'
      : openPullTaskIds.has(card.taskId) && !task?.resumeWork ? 'open pull request already exists for task'
      : !prompt ? 'no canonical prompt found'
      : task && ['claimed', 'interrupted', 'awaiting-review', 'complete', 'dead-letter', 'withdrawn'].includes(task.state) ? `durable state: ${task.state}` : null;
    if (!reason && prompt) {
      // Unmet dependencies skip this card only. Later cards are still considered.
      const missing = prompt.dependencies.filter(id => !complete.has(id));
      if (missing.length) reason = `unmet dependencies: ${missing.join(', ')}`;
      else if (activeIds.some(id => prompt.conflicts.includes(id) || byId.get(id)?.conflicts.includes(prompt.id))) reason = 'conflicts with active work';
    }
    if (card.taskId) seen.add(card.taskId);
    decisions.push({ position: card.position, status: card.status, issue: card.issue, taskId: card.taskId,
      reason: reason ?? (selected ? 'eligible; one task per run' : 'selected') });
    if (!reason && !selected) selected = { ...card, prompt: prompt.file, promptHash: prompt.hash, generated: prompt.generated ?? null };
  }
  return { selected, decisions, blocker: selected ? null : 'No eligible card' };
}
