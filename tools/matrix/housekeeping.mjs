// Steps the board tick runs before it considers new work. Each is safe to repeat and never starts Claude.
import { recoverCiComments } from './ci-comment.mjs';
import { recoverInFlight } from './recover.mjs';
import { resumeBlocked, blockStopped } from './blocked.mjs';
import { advanceDelivery } from './delivery.mjs';
import { readState } from './state.mjs';

// Each step gets { dir, board, pulls, io, clock, config }.
export function standardHousekeeping() {
  return [
    // Retry CI-passed notes that failed to post.
    ({ dir, io }) => recoverCiComments(dir, { io }),
    // A restart must not lose work whose branch is pushed and whose pull request is open.
    ({ dir, pulls, io, clock }) => (io.prChecks ? recoverInFlight(dir, pulls, io, { now: clock }) : null),
    // Merged work: verify the release, comment, close the issue, move the card to Done. Never recodes it.
    async ({ dir, io, config }) => {
      const psGallery = config?.delivery?.psGallery?.enabled === true;
      for (const [id, delivery] of Object.entries(readState(dir, { restart: false }).deliveries ?? {})) if (delivery.stage !== 'done') await advanceDelivery(dir, id, io, { psGallery });
    },
    // An owner moving a card back to Todo or Doing is the explicit resume.
    ({ dir, board, pulls, io }) => resumeBlocked(dir, board, io, { pulls }),
    // Stopped work is reported once and parked in Blocked.
    async ({ dir, board, io }) => {
      for (const itemId of (await blockStopped(dir, io)).moved) { const card = board.cards.find(c => c.itemId === itemId); if (card) card.status = 'Blocked'; }
    },
  ];
}
