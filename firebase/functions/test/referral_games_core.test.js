"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { pickWinningTicket } = require("../lib/referral_games_core");

test("no tickets means no winner", () => {
  assert.equal(pickWinningTicket([]), null);
  assert.equal(pickWinningTicket(undefined), null);
});

test("a single ticket always wins", () => {
  const result = pickWinningTicket(
    [{ inviter_uid: "uid-1" }],
    () => 0,
  );
  assert.equal(result.winnerUid, "uid-1");
  assert.equal(result.winnerTicketCount, 1);
  assert.equal(result.totalTicketCount, 1);
});

test("more validated referrals means more tickets means more chances", () => {
  // uid-1 a parraine 3 fois, uid-2 une seule fois : 4 tickets au total.
  const tickets = [
    { inviter_uid: "uid-1" },
    { inviter_uid: "uid-1" },
    { inviter_uid: "uid-1" },
    { inviter_uid: "uid-2" },
  ];

  const winsPerUid = { "uid-1": 0, "uid-2": 0 };
  const trials = 4000;
  let cursor = 0;
  // randomInt deterministe qui parcourt les 4 index en boucle un nombre de
  // fois proportionnel a leur poids reel -- verifie que winnerTicketCount
  // reflete bien le nombre de tickets de la personne tiree, quel que soit
  // l'index tire.
  for (let i = 0; i < trials; i += 1) {
    const index = cursor % tickets.length;
    cursor += 1;
    const result = pickWinningTicket(tickets, () => index);
    winsPerUid[result.winnerUid] += 1;
    assert.equal(
      result.winnerTicketCount,
      tickets.filter((t) => t.inviter_uid === result.winnerUid).length,
    );
  }

  // Sur un parcours uniforme des index, uid-1 (3 tickets) doit gagner 3x
  // plus souvent que uid-2 (1 ticket).
  assert.equal(winsPerUid["uid-1"], trials * 3 / 4);
  assert.equal(winsPerUid["uid-2"], trials * 1 / 4);
});

test("winning ticket without inviter_uid resolves to an empty winnerUid", () => {
  const result = pickWinningTicket([{}], () => 0);
  assert.equal(result.winnerUid, "");
  assert.equal(result.winnerTicketCount, 1);
});
