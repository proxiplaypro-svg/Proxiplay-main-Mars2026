const test = require('node:test');
const assert = require('node:assert/strict');
const {inspectIntegrity} = require('../scripts/audit_game_integrity');
const ref = path => ({path});

test('historical platform source and missing code require review without repair or code disclosure', () => {
  const findings = inspectIntegrity({userPaths: new Set(['users/a']), links: [], sources: [], prizes: [
    {path: 'prizes/legacy', data: {animation_id: 'old', prize_type: 'principal', winner_id: ref('users/a')}},
    {path: 'prizes/no_code', data: {fulfillment_type: 'platform', winner_id: ref('users/a')}},
  ]});
  assert.ok(findings.some(f => f.kind === 'platform_source_missing_or_wrong_fulfillment'));
  assert.ok(findings.some(f => f.kind === 'operator_prize_missing_code'));
});
test('audit distinguishes missing links, wrong owners, orphans, duplicates and unmaterialized winners', () => {
  const findings = inspectIntegrity({now: 100, userPaths: new Set(['users/a']),
    prizes: [{path: 'prizes/p', data: {winner_id: ref('users/a'), game_id: ref('games/g'), usage_deadline: {toMillis: () => 1}}}],
    links: [1, 2].map(i => ({path: `users/b/my_lots/${i}`, data: {prize_id: ref('prizes/p')}})).concat([{path: 'users/a/my_lots/orphan', data: {prize_id: ref('prizes/missing')}}]),
    sources: [{path: 'games/g', data: {hasWinner: true, main_prize_winner: ref('users/c')}}],
  });
  const kinds = new Set(findings.map(f => f.kind));
  for (const kind of ['missing_my_lot', 'my_lot_wrong_owner', 'orphan_my_lot', 'duplicate_my_lots', 'winner_without_matching_prize', 'expired_unclaimed']) assert.ok(kinds.has(kind), kind);
  assert.ok(!JSON.stringify(findings).includes('claim_code'));
});
test('finalized empty draw is distinguished from missed draw', () => {
  const findings = inspectIntegrity({prizes: [], links: [], userPaths: new Set(), sources: [
    {path: 'animations/empty', data: {status: 'ended', draw_status: 'no_eligible_entries'}},
    {path: 'animations/missed', data: {status: 'ended'}},
  ]});
  assert.deepEqual(findings, [{kind: 'ended_without_winner_needs_review', path: 'animations/missed'}]);
});
