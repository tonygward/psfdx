// Constants and pure decisions in one place. The owner's decisions are in docs/execution-policy.md.
export const WEEKLY_LIMIT_PERCENT = 60;
export const DAILY_TIME = '02:00';
export const TIME_ZONE = 'Europe/London';
export const BATCH_LIMIT = 1;
export const MODEL = 'sonnet';
export const MAXIMUM_RUN_MINUTES = 120;
export const MAXIMUM_REPAIRS = 3;
export const TELEMETRY_SOURCE = 'claude-code-usage-report-weekly-all';

export function usageGate(snapshot, now = Date.now()) {
  if (!snapshot || snapshot.source !== TELEMETRY_SOURCE) return { allowed: false, reason: 'No verified weekly subscription telemetry', snapshot: null };
  const { percentage, observedAt, resetsAt } = snapshot;
  const age = now - Date.parse(observedAt), reset = Date.parse(resetsAt);
  if (typeof percentage !== 'number' || !Number.isFinite(percentage) || percentage < 0 || percentage > 100
    || !Number.isFinite(age) || age < 0 || age > 60000
    || !Number.isFinite(reset) || reset <= now || reset > now + 8 * 86400000) {
    return { allowed: false, reason: 'Malformed, stale or contradictory weekly telemetry', snapshot: null };
  }
  const allowed = percentage < WEEKLY_LIMIT_PERCENT;
  return { allowed, reason: allowed ? `Weekly usage below ${WEEKLY_LIMIT_PERCENT}%` : `Weekly usage at or above ${WEEKLY_LIMIT_PERCENT}%`, snapshot };
}

export function londonDay(now = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

// True once per London day, on the first check at or after the daily time.
export function dailyDue(lastDay, time = DAILY_TIME, now = new Date()) {
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) throw new Error('Invalid dailyTime');
  const clock = new Intl.DateTimeFormat('en-GB', { timeZone: TIME_ZONE, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(now);
  return lastDay !== londonDay(now) && clock >= time;
}
