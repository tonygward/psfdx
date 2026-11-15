// GitHub-backed io for the pickup code. Every call goes through an injected `gh(args)` that returns stdout, so tests need
// no network and the caller decides which token each call holds. `gh` moves cards (the board token: Projects scope only, so it cannot
// touch issues or code). `issueGh` reads and writes issues and pull requests (the worker account: Issues write, no admin). Arguments are passed
// as an array and never through a shell.
// Card moves use the GraphQL mutation: `gh project item-edit` needs the read:org scope, which the board token does not have.
const MOVE = 'mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}';

// Hidden marker for a comment, so a retry never posts twice: <!-- matrix:<kind>:<task>:<detail> -->
export const commentMarker = (kind, task, detail = '') => `<!-- matrix:${kind}:${task}${detail ? `:${detail}` : ''} -->`;

export function githubIo(gh, { projectId, statusFieldId, options = {}, issueGh } = {}) {
  const issues = issueGh ?? gh;
  const json = async args => JSON.parse(await issues(args));
  const move = async (name, itemId) => {
    const optionId = options[name];
    if (!projectId || !statusFieldId || !optionId) throw new Error(`Board ${name} field is not configured`);
    await gh(['api', 'graphql', '-f', `query=${MOVE}`, '-f', `p=${projectId}`, '-f', `i=${itemId}`, '-f', `f=${statusFieldId}`, '-f', `o=${optionId}`]);
  };
  return {
    issueBody: async (repository, issue) => (await json(['issue', 'view', String(issue), '--repo', repository, '--json', 'body'])).body ?? '',
    hasComment: async (repository, issue, marker) => {
      const data = await json(['issue', 'view', String(issue), '--repo', repository, '--json', 'comments']);
      return data.comments.some(comment => comment.body.includes(marker));
    },
    // Head commit and check roll-up of an open pull request, for recovery after a restart.
    prChecks: async (repository, number) => {
      const pull = await json(['pr', 'view', String(number), '--repo', repository, '--json', 'headRefOid,statusCheckRollup']);
      return { headSha: pull.headRefOid, checks: pull.statusCheckRollup ?? [] };
    },
    comment: async (repository, issue, body) => { await issues(['issue', 'comment', String(issue), '--repo', repository, '--body', body]); },
    closeIssue: async (repository, issue) => { await issues(['issue', 'close', String(issue), '--repo', repository, '--reason', 'completed']); },
    moveToDoing: itemId => move('doing', itemId),
    moveToBlocked: itemId => move('blocked', itemId),
    moveToDone: itemId => move('done', itemId),
  };
}
