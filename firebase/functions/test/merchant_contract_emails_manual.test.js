// Version minimale (suivi manuel) : textes de paymentInvitation,
// activationNotice et renewalFailedNotice. Aucune promesse d'« espace
// commercant » pour les factures, la desactivation du renouvellement ou le
// moyen de paiement ; montants, dates et liens inchanges. Fonctions pures.
const test = require('node:test');
const assert = require('node:assert/strict');
const emails = require('../merchant_contract_emails');

const contract = {
  owner_email: 'merchant@example.test', enseigne_id: 'e1', enseigne_name: 'Boutique du port',
  offer: {label: 'Autonome', first_year_ht_cents: 36500, first_year_ttc_cents: 43800},
};
// 15/12/2026 et 01/12/2027 a Paris.
const kExpires = Date.UTC(2026, 11, 15, 22, 59, 59, 999);
const kActivated = Date.UTC(2026, 11, 1, 9);
const kPeriodEnd = Date.UTC(2027, 11, 1, 9);
const kGrace = Date.UTC(2027, 11, 16, 22, 59, 59, 999);
const kUrl = 'https://www.proxiplay.fr/espace-commercant/?paiement=abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';
const kInvoiceUrl = 'https://invoice.stripe.com/i/test_renewal';

// « espace commercant » n'est permis que pour la page de paiement (invitation).
const kForbidden = /(facture|moyen de paiement|désactiv)[^.\n]*espace commerçant|espace commerçant[^.\n]*(facture|moyen de paiement|désactiv)/i;

test('invitation : facture par e-mail ; montants, date et lien inchanges', () => {
  const m = emails.paymentInvitation(contract, 'c1', {url: kUrl, expiresMs: kExpires});
  assert.match(m.text, /438,00 € TTC, soit 365,00 € HT/);
  assert.ok(m.text.includes(`\n${kUrl}\n`), 'lien inchange, seul sur sa ligne');
  assert.match(m.text, /valable jusqu'au 15\/12\/2026 inclus \(quinze jours, CGV art\. 8\.1\)/);
  assert.match(m.text, /La facture vous est ensuite envoyée par e-mail\./);
  assert.doesNotMatch(m.text, kForbidden);
  assert.doesNotMatch(m.text, /checkout\.stripe\.com|buy\.stripe\.com/);
});

test('activation : facture par e-mail, desactivation et moyen de paiement par contact@proxiplay.fr', () => {
  const m = emails.activationNotice(contract, 'c1', {activatedMs: kActivated, periodEndMs: kPeriodEnd});
  assert.doesNotMatch(m.text, /espace commerçant/);
  assert.match(m.text, /est activé le 01\/12\/2026 : c'est le point de départ de la période annuelle \(CGV, art\. 8\.2\)/);
  assert.match(m.text, /Échéance de cette période : 01\/12\/2027\. Le renouvellement est automatique pour douze mois\./);
  assert.match(m.text, /Pour désactiver le renouvellement, écrivez à contact@proxiplay\.fr : votre demande doit nous parvenir au moins sept jours avant l'échéance\. Nous vous confirmons la désactivation par e-mail \(art\. 9\)\./);
  assert.match(m.text, /Pour changer de moyen de paiement, écrivez à contact@proxiplay\.fr : nous vous renvoyons un lien sécurisé\./);
  assert.match(m.text, /Référence : c1\. La facture vous est envoyée par e-mail\./);
});

test('activation sans date d\'echeance : aucune date inventee, memes modalites', () => {
  const m = emails.activationNotice(contract, 'c1', {activatedMs: kActivated, periodEndMs: null});
  assert.doesNotMatch(m.text, /Échéance de cette période/);
  assert.match(m.text, /au moins sept jours avant l'échéance/);
  assert.doesNotMatch(m.text, /espace commerçant/);
});

test('echec du renouvellement : lien de facture inchange, desactivation possible pendant le delai (art. 11)', () => {
  const m = emails.renewalFailedNotice(contract, 'c1', {graceUntilMs: kGrace, invoiceUrl: kInvoiceUrl});
  assert.doesNotMatch(m.text, /espace commerçant/);
  assert.match(m.text, /délai de régularisation de quinze jours, jusqu'au 16\/12\/2027 inclus, pendant lequel vos accès sont maintenus \(CGV, art\. 11\)/);
  assert.ok(m.text.includes(`Pour régulariser : ${kInvoiceUrl}\n`), 'lien de la facture inchange');
  assert.match(m.text, /Pour changer de moyen de paiement, écrivez à contact@proxiplay\.fr : nous vous renvoyons un lien sécurisé\./);
  assert.match(m.text, /la désactivation du renouvellement reste possible pendant ce délai de régularisation \(art\. 11\) : écrivez à contact@proxiplay\.fr, nous vous la confirmons par e-mail/);
  assert.match(m.text, /la facture du renouvellement est annulée et aucune pénalité n'est réclamée \(art\. 9\)/);
});

test('echec du renouvellement sans lien de facture : regularisation par contact@proxiplay.fr', () => {
  const m = emails.renewalFailedNotice(contract, 'c1', {graceUntilMs: null, invoiceUrl: null});
  assert.doesNotMatch(m.text, /espace commerçant/);
  assert.match(m.text, /Vous disposez d'un délai de régularisation de quinze jours \(CGV, art\. 11\)\./);
  assert.match(m.text, /Pour régulariser, écrivez à contact@proxiplay\.fr : nous vous renvoyons un lien sécurisé\./);
});
