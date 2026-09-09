const test = require('node:test');
const assert = require('node:assert/strict');
const {runScheduledDraws} = require('../scheduled_draw_runner');
const logger = () => { const errors = []; return {errors, info() {}, error(event, data) { errors.push({event, ...data}); }}; };
test('query failure remains a rejected invocation with job and error code', async () => {
  const log = logger();
  const error = Object.assign(new Error('missing index'), {code: 9});
  await assert.rejects(runScheduledDraws({name: 'animations', logger: log, load: async () => {throw error;}, draw: assert.fail}), e => e === error);
  assert.deepEqual(log.errors, [{event: 'DRAW_QUERY_FAILED', job: 'animations', code: 9}]);
});
test('one failed draw does not skip later draws or report success', async () => {
  const log = logger(); const visited = [];
  await assert.rejects(runScheduledDraws({name: 'monthly', logger: log, load: async () => [{id: 'a'}, {id: 'b'}], draw: async item => {
    visited.push(item.id); if (item.id === 'a') throw new Error('commit failed'); return {status: 'completed'};
  }}), AggregateError);
  assert.deepEqual(visited, ['a', 'b']);
  assert.equal(log.errors[0].id, 'a');
});
test('empty and already drawn runs complete normally', async () => {
  for (const items of [[], [{id: 'a'}]]) assert.equal(await runScheduledDraws({name: 'draw', logger: logger(), load: async () => items, draw: async () => ({status: 'already_drawn'})}), null);
});
