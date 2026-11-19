// Phase 1, tranche 1, lot 1.0 : fonctions pures du modele (sans emulateur).
const test = require('node:test');
const assert = require('node:assert/strict');
const m = require('../merchant_contracts_model');

test('SIRET : 14 chiffres et cle de Luhn ; espaces toleres ; exception La Poste', () => {
  assert.equal(m.isValidSiret('988 968 376 00018'), true);
  assert.equal(m.isValidSiret('98896837600026'), true, 'meme SIREN, autre etablissement');
  assert.equal(m.isValidSiret('98896837600019'), false);
  assert.equal(m.isValidSiret('1234567890123'), false);
  assert.equal(m.isValidSiret('9889683760001A'), false);
  assert.equal(m.isValidSiret(''), false);
  assert.equal(m.isValidSiret(null), false);
  assert.equal(m.isValidSiret('35600000000010'), true, 'La Poste : somme des chiffres multiple de 5');
  assert.equal(m.isValidSiret('35600000000048'), false);
});

test('transitions : tranche 1 = submitted -> confirmed | refused, rien d\'autre', () => {
  m.assertTransition('submitted', 'confirmed');
  m.assertTransition('submitted', 'refused');
  for (const [from, to] of [['confirmed', 'refused'], ['refused', 'confirmed'], ['confirmed', 'submitted'],
    ['submitted', 'active'], ['unknown', 'confirmed']]) {
    assert.throws(() => m.assertTransition(from, to), (error) => error.details?.reason === 'invalid_transition', `${from} -> ${to}`);
  }
});

test('prix : catalogue uniquement, TVA 20 %, remise sur la premiere annee seulement', () => {
  const base = m.offerSnapshot('autonome');
  assert.equal(base.first_year_ht_cents, 36500);
  assert.equal(base.first_year_ttc_cents, 43800);
  assert.equal(base.renewal_ttc_cents, 43800);
  const acc = m.offerSnapshot('accompagnee');
  assert.equal(acc.first_year_ttc_cents, 120000);
  const promo = m.offerSnapshot('autonome', {discountHtCents: 10000});
  assert.equal(promo.first_year_ht_cents, 26500);
  assert.equal(promo.first_year_ttc_cents, 31800);
  assert.equal(promo.renewal_ht_cents, 36500, 'le renouvellement reste au tarif de reference (art. 6)');
  assert.throws(() => m.offerSnapshot('custom'), /Offre inconnue/);
  assert.throws(() => m.offerSnapshot(''), /Offre inconnue/);
});

test('vue commercant : aucune donnee interne, meme si elle etait presente par erreur dans le document', () => {
  const view = m.merchantView('c1', {
    owner_uid: 'merchant', state: 'refused', siret: '98896837600018',
    public_refusal: {motif: 'activity', detail: 'Activite exclue'},
    verification: {checks: {fraud: {result: 'fail', note: 'note interne'}}},
    refusal_reason: 'note interne', events: [{type: 'x'}], ip: '203.0.113.9',
    origin: {type: 'demarchee', rep_id: 'rep1', evidence: {link_hash: 'abc'}},
  });
  const text = JSON.stringify(view);
  for (const forbidden of ['verification', 'note interne', 'events', '203.0.113.9', 'rep1', 'link_hash', 'refusal_reason']) {
    assert.ok(!text.includes(forbidden), forbidden);
  }
  assert.equal(view.origin, 'demarchee');
  assert.deepEqual(view.refusal, {motif: 'activity', detail: 'Activite exclue'});
});

test('propriete d\'une enseigne : meme contrat que les regles (owner ou owner_id, chaine ou reference)', () => {
  assert.equal(m.ownsEnseigne({owner: {path: 'users/u1'}}, 'u1'), true);
  assert.equal(m.ownsEnseigne({owner: '/users/u1', owner_id: {path: 'users/u1'}}, 'u1'), true);
  assert.equal(m.ownsEnseigne({owner: {path: 'users/u2'}}, 'u1'), false);
  assert.equal(m.ownsEnseigne({owner: {path: 'users/u1'}, owner_id: {path: 'users/u2'}}, 'u1'), false, 'identites en conflit');
  assert.equal(m.ownsEnseigne({}, 'u1'), false);
});
