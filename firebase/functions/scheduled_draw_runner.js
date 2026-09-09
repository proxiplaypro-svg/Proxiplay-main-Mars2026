// A failed draw must fail the scheduled invocation, after trying other draws.
async function runScheduledDraws({name, load, draw, logger}) {
  let items;
  try {
    items = await load();
  } catch (error) {
    logger.error('DRAW_QUERY_FAILED', {job: name, code: error.code || null});
    throw error;
  }
  logger.info('DRAW_RUN_STARTED', {job: name, count: items.length});
  const failures = [];
  for (const item of items) {
    try {
      const result = await draw(item);
      if (result?.status === 'manual_review_required') throw new Error('manual_review_required: ' + (result.reason || 'award conflict'));
      logger.info(result?.status === 'completed' ? 'DRAW_SUCCESS' : 'DRAW_SKIPPED', {job: name, id: item.id, status: result?.status || 'completed'});
    } catch (error) {
      failures.push(error);
      logger.error('DRAW_FAILED', {job: name, id: item.id, code: error.code || null});
    }
  }
  if (failures.length) throw new AggregateError(failures, `${name}: ${failures.length} draw(s) failed`);
  return null;
}
module.exports = {runScheduledDraws};
