// A failed draw must fail the scheduled invocation, after trying other draws.
//
// concurrency/timeBudgetMs default to 1 and Infinity, which reproduces
// the previous strictly-sequential, unbounded behavior exactly -- the
// other three callers (drawAnimationWinners, drawReferralGameWinner,
// drawMonthlyChallengeWinner) never pass these and are unaffected.
// pickMainPrizeWinners opts into both: Gen1 scheduled functions kept
// timing out at 60s because dozens of already-settled games were
// processed one at a time before ever reaching genuinely pending ones.
// With concurrency>1, items are pulled from a shared cursor by a small
// pool of workers (safe: each draw() touches a different gameId, no
// cross-document contention). timeBudgetMs stops *starting* new draws
// once the run is close to the function's own timeout, logging every
// remaining candidate as DRAW_DEFERRED instead of letting the
// infrastructure kill the invocation silently -- deferred candidates are
// simply picked up again by the next scheduled run's load() query.
async function runScheduledDraws({name, load, draw, logger, concurrency = 1, timeBudgetMs = Infinity}) {
  let items;
  try {
    items = await load();
  } catch (error) {
    logger.error('DRAW_QUERY_FAILED', {job: name, code: error.code || null});
    throw error;
  }
  logger.info('DRAW_RUN_STARTED', {job: name, count: items.length});
  const startedAt = Date.now();
  const failures = [];
  let cursor = 0;
  let deferred = 0;

  async function worker() {
    while (cursor < items.length) {
      if (Date.now() - startedAt > timeBudgetMs) {
        for (; cursor < items.length; cursor += 1) {
          deferred += 1;
          logger.error('DRAW_DEFERRED', {job: name, id: items[cursor].id, reason: 'time_budget_exceeded'});
        }
        break;
      }
      const item = items[cursor];
      cursor += 1;
      try {
        const result = await draw(item);
        if (result?.status === 'manual_review_required') throw new Error('manual_review_required: ' + (result.reason || 'award conflict'));
        logger.info(result?.status === 'completed' ? 'DRAW_SUCCESS' : 'DRAW_SKIPPED', {job: name, id: item.id, status: result?.status || 'completed'});
      } catch (error) {
        failures.push(error);
        logger.error('DRAW_FAILED', {job: name, id: item.id, code: error.code || null});
      }
    }
  }

  const workerCount = Math.max(1, Math.min(concurrency, items.length));
  await Promise.all(Array.from({length: workerCount}, worker));

  if (deferred > 0) {
    logger.error('DRAW_RUN_TIME_BUDGET_EXCEEDED', {job: name, deferred, total: items.length});
  }
  if (failures.length) throw new AggregateError(failures, `${name}: ${failures.length} draw(s) failed`);
  return null;
}
module.exports = {runScheduledDraws};
