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

// --- Regression: pickMainPrizeWinners Gen1 timeout incident ---
// Production logs showed DRAW_RUN_STARTED, dozens of DRAW_SKIPPED
// processed one at a time, then "finished with status: 'timeout'" every
// night since 01/10: a long sequential tail of already-settled games
// consumed the whole 60s budget before genuinely pending games later in
// the list were ever reached. These tests cover the two knobs added to
// fix that: bounded concurrency (so a long list is processed faster, not
// starving later items) and a soft time budget (so if the list is ever
// too long anyway, the run degrades gracefully -- deferring and logging
// explicitly -- rather than being killed silently by the infrastructure
// timeout). Both default to the previous strictly-sequential, unbounded
// behavior, so the other three scheduled callers (drawAnimationWinners,
// drawReferralGameWinner, drawMonthlyChallengeWinner), none of which
// pass these options, are unaffected -- already proven by the first
// three tests above still passing unchanged.

test('bounded concurrency reaches every item, including real candidates placed after a long tail of skips', async () => {
  const log = logger();
  const items = Array.from({length: 20}, (_, i) => ({id: `skip${i}`}));
  items.push({id: 'real1'}, {id: 'real2'}, {id: 'real3'});
  const visited = [];
  const draw = async (item) => {
    await new Promise((resolve) => setTimeout(resolve, 2));
    visited.push(item.id);
    return item.id.startsWith('real') ? {status: 'completed'} : {status: 'no_main_prize'};
  };
  const result = await runScheduledDraws({
    name: 'pickMainPrizeWinners', logger: log, load: async () => items, draw,
    concurrency: 8, timeBudgetMs: 10000,
  });
  assert.equal(result, null);
  assert.equal(visited.length, items.length, 'every item must be visited, none starved');
  for (const id of ['real1', 'real2', 'real3']) assert.ok(visited.includes(id), `${id} must have been reached`);
  assert.equal(log.errors.length, 0, 'no DRAW_FAILED/DRAW_DEFERRED expected when well within the time budget');
});

test('concurrent processing still isolates one failed draw from the others', async () => {
  const log = logger();
  const items = [{id: 'a'}, {id: 'b'}, {id: 'c'}, {id: 'd'}];
  const visited = [];
  await assert.rejects(
    runScheduledDraws({
      name: 'pickMainPrizeWinners', logger: log, concurrency: 4, load: async () => items,
      draw: async (item) => {
        visited.push(item.id);
        if (item.id === 'b') throw new Error('commit failed');
        return {status: 'completed'};
      },
    }),
    AggregateError,
  );
  assert.equal(visited.length, 4, 'a failure on one item must not prevent the others from being attempted');
  assert.ok(log.errors.some((e) => e.event === 'DRAW_FAILED' && e.id === 'b'));
});

test('time budget stops starting new draws near the deadline, logs DRAW_DEFERRED for the rest, and does not fail the run by itself', async () => {
  const log = logger();
  const items = Array.from({length: 10}, (_, i) => ({id: `g${i}`}));
  const visited = [];
  const draw = async (item) => {
    await new Promise((resolve) => setTimeout(resolve, 20));
    visited.push(item.id);
    return {status: 'completed'};
  };
  const result = await runScheduledDraws({
    name: 'pickMainPrizeWinners', logger: log, load: async () => items, draw,
    concurrency: 1, timeBudgetMs: 35,
  });
  assert.equal(result, null, 'a time-budget deferral is a graceful degradation, not a failure');
  assert.ok(visited.length < items.length, 'not every item should be reached before the budget runs out');
  const deferredEvents = log.errors.filter((e) => e.event === 'DRAW_DEFERRED');
  assert.equal(deferredEvents.length, items.length - visited.length);
  const summary = log.errors.find((e) => e.event === 'DRAW_RUN_TIME_BUDGET_EXCEEDED');
  assert.ok(summary, 'a summary event must be logged so the deferral is visible in monitoring');
  assert.equal(summary.deferred, items.length - visited.length);
});

test('deferred items are picked up again on a later run -- they are not marked as a kind of failure anywhere', async () => {
  const log = logger();
  // Simulates "next night's run": the same item that would have been
  // deferred is simply offered again by load() and succeeds normally.
  const result = await runScheduledDraws({
    name: 'pickMainPrizeWinners', logger: log, load: async () => [{id: 'deferred_yesterday'}],
    draw: async () => ({status: 'completed'}),
  });
  assert.equal(result, null);
  assert.equal(log.errors.length, 0);
});
