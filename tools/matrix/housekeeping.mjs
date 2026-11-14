// Steps the board tick runs before it considers new work. Each is safe to repeat and never starts Claude.
import { recoverCiComments } from './ci-comment.mjs';
import { recoverInFlight } from './recover.mjs';
import { resumeBlocked, blockStopped } from './blocked.mjs';

// Each step gets { dir, board, pulls, io, clock }. Later prompts (delivery) add their own steps to this list.
export function standardHousekeeping() {
  return [
    // Retry CI-passed notes that failed to post.
    ({ dir, io }) => recoverCiComments(dir, { io }),
    // A restart must not lose work whose branch is pushed and whose pull request is open.
    ({ dir, pulls, io, clock }) => (io.prChecks ? recoverInFlight(dir, pulls, io, { now: clock }) : null),
    // An owner moving a card back to Todo or Doing is the explicit resume.
    ({ dir, board, pulls, io }) => resumeBlocked(dir, board, io, { pulls }),
    // Stopped work is reported once and parked in Blocked.
    async ({ dir, board, io }) => {
      for (const itemId of (await blockStopped(dir, io)).moved) { const card = board.cards.find(c => c.itemId === itemId); if (card) card.status = 'Blocked'; }
    },
  ];
}
