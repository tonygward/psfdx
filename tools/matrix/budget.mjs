// Run budget: total elapsed time for one run, counted from the first claim and kept in the saved state,
// so a restart cannot reset it. Only an explicit resume starts a new budget. CI and publication waiting count.
export const DEFAULT_RUN_MINUTES = 120;

export const runMinutes = worker => worker?.maximumRunMinutes ?? DEFAULT_RUN_MINUTES;

// Optional token budget for one run (owner safety net, on top of the turn and cost limits per attempt). Counts the tokens
// Claude reports for each attempt: input, output and cache writes. Cache reads are re-reads of context already counted, so
// they are left out. Checked between attempts: a single attempt is bounded by its own turn and cost limits.
export const tokensUsed = usage => ['input_tokens', 'output_tokens', 'cache_creation_input_tokens']
  .reduce((sum, key) => sum + (Number.isFinite(usage?.[key]) && usage[key] > 0 ? usage[key] : 0), 0);

export function tokenStop(task, worker) {
  const limit = worker?.maximumTokens;
  if (!Number.isInteger(limit)) return null;
  return (task?.tokensUsed ?? 0) >= limit ? `Run token limit of ${limit} tokens reached (${task.tokensUsed} used)` : null;
}

/** Returns the reason the run must stop, or null while there is budget left. */
export function budgetStop(task, worker, nowMs) {
  const started = Date.parse(task?.runStartedAt);
  if (!Number.isFinite(started)) return null;
  const limit = runMinutes(worker);
  return nowMs - started >= limit * 60000 ? `Run time limit of ${limit} minutes reached (counted from the first claim, including CI waiting)` : null;
}

export const DEFAULT_REPAIRS = 3;
export const repairLimit = worker => worker?.maximumRepairs ?? DEFAULT_REPAIRS;
