#!/usr/bin/env node
// Read-only. No repair mode. Reports document paths, never claim codes or emails.
// node scripts/audit_game_integrity.js --project=PROJECT > integrity.json
function refPath(value) { return typeof value?.path === 'string' ? value.path : ''; }
function userPath(value) {
  const path=refPath(value)||String(typeof value==='string'?value:'').replace(/^\//,'');
  return /^users\/[^/]+$/.test(path)?path:'';
}
function shopOwnerPath(data={}) {
  const primary=userPath(data.owner_id), legacy=userPath(data.owner);
  return (data.owner_id!=null&&!primary)||(data.owner!=null&&!legacy)||(primary&&legacy&&primary!==legacy)?'':primary||legacy;
}
function millis(value) { return typeof value?.toMillis === 'function' ? value.toMillis() : null; }
function inspectIntegrity({prizes, links, sources, userPaths, shops = [], projections = [], referrals = [], tickets = [], pending = [], now = Date.now()}) {
  const findings = [];
  const report = (kind, path, related = '') => findings.push({kind, path, ...(related ? {related} : {})});
  const prizeMap = new Map(prizes.map(p => [p.path, p]));
  const sourceMap = new Map(sources.map(s => [s.path, s]));
  const shopMap = new Map(shops.map(s => [s.path, s]));
  const projectionPaths = new Set(projections.map(p => p.path));
  const linksByPrize = new Map();
  for (const link of links) {
    const prizePath = refPath(link.data.prize_id);
    if (!prizePath || !prizeMap.has(prizePath)) { report('orphan_my_lot', link.path, prizePath); continue; }
    const owner = link.path.split('/').slice(0, 2).join('/');
    const prize = prizeMap.get(prizePath);
    if (refPath(prize.data.winner_id) !== owner) report('my_lot_wrong_owner', link.path, prizePath);
    if (!userPaths.has(owner)) report('my_lot_missing_user', link.path, owner);
    const existing = linksByPrize.get(prizePath) || [];
    existing.push(link.path); linksByPrize.set(prizePath, existing);
  }
  const awards = new Map();
  for (const prize of prizes) {
    const platformSource = prize.data.animation_id || prize.data.referral_game_id || prize.data.monthly_challenge_id || prize.data.monthly_challenge_draw_ref;
    if (platformSource && !['platform', 'partner'].includes(prize.data.fulfillment_type)) report('platform_source_missing_or_wrong_fulfillment', prize.path);
    if (['platform', 'partner'].includes(prize.data.fulfillment_type) && !prize.data.claim_code) report('operator_prize_missing_code', prize.path);
    const fulfillment = prize.data.fulfillment_type || (['animation','referral_game','monthly_challenge'].includes(prize.data.prize_type) ? 'platform' : 'merchant');
    if (fulfillment === 'merchant' && (!refPath(prize.data.owner_id) || !refPath(prize.data.enseigne_id))) report('merchant_prize_missing_owner_or_shop', prize.path);
    if (fulfillment === 'partner' && (!refPath(prize.data.partner_ref) || refPath(prize.data.partner_ref)!==refPath(prize.data.enseigne_id) || prize.data.owner_id!=null)) report('partner_prize_invalid_delivery_shape', prize.path);
    const winner = refPath(prize.data.winner_id);
    const linked = linksByPrize.get(prize.path) || [];
    if (!/^users\/[^/]+$/.test(winner)) report('invalid_prize_winner', prize.path);
    else {
      if (!userPaths.has(winner)) report('prize_missing_user', prize.path, winner);
      if (!linked.some(p => p.startsWith(`${winner}/my_lots/`))) report('missing_my_lot', prize.path, winner);
    }
    if (linked.length > 1) report('duplicate_my_lots', prize.path);
    const deadline = millis(prize.data.usage_deadline);
    if (prize.data.usage_deadline != null && deadline == null) report('invalid_deadline', prize.path);
    if (!prize.data.claimed && deadline != null && deadline < now) report('expired_unclaimed', prize.path);
    const source = refPath(prize.data.game_id) ||
      (prize.data.animation_id ? `animations/${prize.data.animation_id}` : '') ||
      (prize.data.referral_game_id ? `referral_games/${prize.data.referral_game_id}` : '') ||
      refPath(prize.data.monthly_challenge_draw_ref);
    if (source) {
      if (!sourceMap.has(source)) report('prize_missing_source', prize.path, source);
      const list = awards.get(source) || []; list.push(prize); awards.set(source, list);
    }
  }
  for (const source of sources) {
    const d = source.data;
    if (source.path.startsWith('games/')) {
      const shop = shopMap.get(refPath(d.enseigne_id) || refPath(d.enseigne_ref));
      const owner = userPath(d.owner_id);
      const shopOwner = shop ? shopOwnerPath(shop.data) : '';
      const ownerlessManaged = shop?.data.managed_by_admin===true && shop?.data.owner_id==null && shop?.data.owner==null;
      if (!shop) report('game_missing_enseigne', source.path);
      else if (ownerlessManaged) {
        if (d.owner_id!=null) report('managed_game_has_merchant_owner', source.path);
        if (!userPath(d.create_by)) report('managed_game_missing_creator', source.path);
      } else if (!owner || owner!==shopOwner) report('game_owner_shop_mismatch', source.path);
    }
    const winner = refPath(d.main_prize_winner) || refPath(d.winner_ref) || (d.winner_uid ? `users/${d.winner_uid}` : '');
    if (winner && source.path.startsWith('animations/') && !projectionPaths.has(source.path + '/public_winner/current')) report('animation_missing_public_winner', source.path);
    const won = (awards.get(source.path) || []).filter(p => p.data.prize_type !== 'secondaire');
    if (winner && !won.some(p => refPath(p.data.winner_id) === winner)) report('winner_without_matching_prize', source.path, winner);
    if (won.length > 1) report('multiple_final_prizes', source.path);
    const terminalEmpty = ['no_eligible_entries', 'no_eligible_users'].includes(d.draw_status || d.status);
    const ended = (millis(d.end_date) != null && millis(d.end_date) < now) || ['ended', 'completed'].includes(d.status);
    if (ended && !winner && !terminalEmpty && !(source.path.startsWith('games/') && d.hasMainPrize === false)) report('ended_without_winner_needs_review', source.path);
    if (d.hasWinner === true && !winner) report('hasWinner_without_winner_reference', source.path);
  }
  for (const referral of referrals) {
    if (referral.data.status !== 'accepted') continue;
    const id=referral.path.split('/').pop();
    const event=pending.find(p=>p.path==='referral_reward_pending/'+id);
    const matchingGames=sources.filter(s=>s.path.startsWith('referral_games/') && millis(s.data.start_date)<=millis(referral.data.acceptedAt) && millis(s.data.end_date)>=millis(referral.data.acceptedAt));
    if ((event?.data.mode==='game' || matchingGames.length) && !tickets.some(t=>t.data.referral_id===id || t.path.endsWith('/entries/'+id))) report('referral_acceptance_without_ticket', referral.path);
    if (event && event.data.status!=='granted') report('referral_reward_'+event.data.status,event.path);
  }
  return findings;
}
async function main() {
  const args = process.argv.slice(2);
  const project = args.find(a => a.startsWith('--project='))?.slice(10);
  if (!project || args.some(a => !a.startsWith('--project='))) throw new Error('Usage: --project=PROJECT (read-only; no other flags)');
  const admin = require('firebase-admin');
  admin.initializeApp({projectId: project});
  const db = admin.firestore();
  async function scan(query) {
    const docs = []; let cursor;
    do {
      let page = query.orderBy(admin.firestore.FieldPath.documentId()).limit(250);
      if (cursor) page = page.startAfter(cursor);
      const snap = await page.get();
      docs.push(...snap.docs.map(d => ({path: d.ref.path, data: d.data()})));
      cursor = snap.size === 250 ? snap.docs[snap.size - 1] : null;
    } while (cursor);
    return docs;
  }
  try {
    const prizes = await scan(db.collection('prizes'));
    const links = await scan(db.collectionGroup('my_lots'));
    const sources = [];
    for (const name of ['games', 'animations', 'referral_games', 'monthly_challenge_draws']) sources.push(...await scan(db.collection(name)));
    const users = await scan(db.collection('users'));
    const shops = await scan(db.collection('enseignes'));
    const projections = await scan(db.collectionGroup('public_winner'));
    const referrals = await scan(db.collection('referrals'));
    const pending = await scan(db.collection('referral_reward_pending'));
    const tickets=[];
    for(const game of sources.filter(s=>s.path.startsWith('referral_games/'))) tickets.push(...await scan(db.doc(game.path).collection('entries')));
    const findings = inspectIntegrity({prizes, links, sources, shops, projections, referrals, pending, tickets, userPaths: new Set(users.map(u => u.path))});
    console.log(JSON.stringify({project, readOnly: true, snapshotAtomic: false, generatedAt: new Date().toISOString(),
      counts: {prizes: prizes.length, links: links.length, sources: sources.length}, findings}, null, 2));
  } finally { await admin.app().delete(); }
}
if (require.main === module) main().catch(error => { console.error('AUDIT_FAILED', error.code || '', error.message); process.exitCode = 1; });
module.exports = {inspectIntegrity};
