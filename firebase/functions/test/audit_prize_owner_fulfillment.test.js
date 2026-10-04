// Pure unit tests for scripts/audit_prize_owner_fulfillment.js: buildFinding()
// is Firestore-free (takes already-fetched data), no emulator needed. Never
// asserts on a claim_code value, since the script itself never reads or
// reports that field by design.
const test = require("node:test");
const assert = require("node:assert/strict");
const { buildFinding } = require("../scripts/audit_prize_owner_fulfillment");

const ref = (path) => ({ path });
const createTime = { toDate: () => new Date("2026-09-15T10:00:00Z") };

test("lot platform avec owner_id errone, jamais reclame, aucun job partenaire -> safe_to_review", () => {
  const finding = buildFinding({
    prizeId: "p1",
    data: {
      fulfillment_type: "platform",
      game_id: ref("games/g1"),
      owner_id: ref("users/merchant1"),
      enseigne_id: ref("enseignes/shop1"),
      claimed: false,
      winner_id: ref("users/winner1"),
    },
    createTime,
    hasPartnerDeliveryJob: false,
  });
  assert.equal(finding.prize_id, "p1");
  assert.equal(finding.fulfillment_type, "platform");
  assert.equal(finding.owner_id, "users/merchant1");
  assert.equal(finding.game_id, "games/g1");
  assert.equal(finding.enseigne_id, "enseignes/shop1");
  assert.equal(finding.created_at, "2026-09-15T10:00:00.000Z");
  assert.equal(finding.claimed, false);
  assert.equal(finding.has_winner, true);
  assert.equal(finding.has_partner_delivery_job, false);
  assert.equal(finding.cleanup_signal, "safe_to_review");
  assert.equal("claim_code" in finding, false, "le secret ne doit jamais apparaitre dans un finding");
});

test("lot partner deja reclame -> needs_manual_review, pas safe_to_review", () => {
  const finding = buildFinding({
    prizeId: "p2",
    data: {
      fulfillment_type: "partner",
      owner_id: ref("users/merchant2"),
      claimed: true,
    },
    createTime,
    hasPartnerDeliveryJob: false,
  });
  assert.equal(finding.cleanup_signal, "needs_manual_review");
});

test("lot avec un job de livraison partenaire en cours -> needs_manual_review meme non reclame", () => {
  const finding = buildFinding({
    prizeId: "p3",
    data: {
      fulfillment_type: "partner",
      owner_id: ref("users/merchant3"),
      claimed: false,
    },
    createTime,
    hasPartnerDeliveryJob: true,
  });
  assert.equal(finding.cleanup_signal, "needs_manual_review");
});

test("champs absents (game_id/enseigne_id/winner_id) -> null plutot qu'une erreur", () => {
  const finding = buildFinding({
    prizeId: "p4",
    data: { fulfillment_type: "platform", owner_id: ref("users/m") },
    createTime: null,
    hasPartnerDeliveryJob: false,
  });
  assert.equal(finding.game_id, null);
  assert.equal(finding.enseigne_id, null);
  assert.equal(finding.has_winner, false);
  assert.equal(finding.created_at, null);
});
