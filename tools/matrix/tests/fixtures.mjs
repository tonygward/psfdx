// Recorded-shape GraphQL fixtures and small fakes shared by the board tests. No network.

export const REPO = 'tonygward/psfdx';
export const NOW = Date.parse('2026-11-14T10:00:00Z'); // 10:00 London (GMT): after the 02:00 slot

export const node = ({ id = 'item', status = 'Todo', number, title, state = 'OPEN', repo = REPO, association = 'OWNER', author = 'tonygward' }) => ({
  id: `item-${number ?? id}`,
  status: status === null ? null : { name: status },
  content: number === undefined ? { __typename: 'DraftIssue', title } : { __typename: 'Issue', number, title, state, authorAssociation: association, author: { login: author }, repository: { nameWithOwner: repo } },
});

// A paged GraphQL fake. `pages` is an array of node arrays; `views` is the project's view count.
export function boardGraphql(pages, { views = 1, total = null, failAt = null } = {}) {
  const calls = [];
  const graphql = async (query, variables) => {
    calls.push({ query, variables });
    if (failAt !== null && calls.length === failAt + 1) throw new Error('API error');
    if (query.includes('pullRequests')) throw new Error('unexpected pull request query');
    const index = variables.after ? Number(variables.after.replace('cursor-', '')) : 0;
    const nodes = pages[index];
    return { data: { node: { views: { totalCount: views }, items: {
      totalCount: total ?? pages.flat().length,
      pageInfo: { hasNextPage: index < pages.length - 1, endCursor: `cursor-${index + 1}` }, nodes } } } };
  };
  graphql.calls = calls;
  return graphql;
}

export function combinedGraphql(boardPages, pulls = [], options = {}) {
  const board = boardGraphql(boardPages, options);
  const graphql = async (query, variables) => {
    if (query.includes('pullRequests')) {
      const nodes = pulls.filter(p => p.state === variables.states[0]);
      return { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false, endCursor: null }, nodes } } } };
    }
    return board(query, variables);
  };
  graphql.board = board;
  return graphql;
}

export const prompt = (id, extra = {}) => ({ id, file: `prompts/${id}-x.md`, hash: `hash-${id}-0000000000`, complete: false, priority: 50, effort: 'medium', dependencies: [], conflicts: [], ...extra });
export const usageOk = (percent = 10, now = NOW) => ({ source: 'claude-code-usage-report-weekly-all', percentage: percent, observedAt: new Date(now - 1000).toISOString(), resetsAt: new Date(now + 86400000).toISOString() });
export const usageResult = (percent = 10, now = NOW) => ({ allowed: percent < 60, extraUsageEnabled: false, snapshot: usageOk(percent, now), meters: [], reason: 'ok' });

// A fake GitHub io that records everything it is asked to write.
export function fakeIo({ bodies = {}, comments = [], failComment = false } = {}) {
  const writes = [];
  const existing = [...comments];
  return {
    writes,
    issueBody: async (repository, issue) => bodies[issue] ?? '',
    hasComment: async (repository, issue, marker) => existing.some(body => body.includes(marker)),
    comment: async (repository, issue, body) => { if (failComment) throw new Error('network down'); writes.push({ kind: 'comment', issue, body }); existing.push(body); },
    moveToDoing: async itemId => { writes.push({ kind: 'doing', itemId }); },
    moveToBlocked: async itemId => { writes.push({ kind: 'blocked', itemId }); },
    moveToDone: async itemId => { writes.push({ kind: 'done', itemId }); },
  };
}

export const goodBody = [
  '## Objective', 'Make the thing work so that users can rely on it every single day.', '',
  '## Scope', 'Change the module so that it builds the correct command string for the feature.', '',
  '## Acceptance criteria', 'The cmdlet returns the expected records for a successful result.', '',
  '## Tests', 'A Pester test asserts the exact sf command string that is built.', ''].join('\n');

