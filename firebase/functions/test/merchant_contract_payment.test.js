// Phase 1, tranche 2a, lot 1.6 : invitation a payer, lien de 15 jours, file
// de reprise des e-mails.
const h = require('./merchant_contracts_helpers.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const mail = require('../merchant_contract_mail');
const cgvDocument = require('../merchant_cgv_document');
const paris = require('../paris_time');
const {submitMerchantSubscriptionRequestHandler} = require('../merchant_contracts_request');
const review = require('../merchant_contract_review');
const origin = require('../merchant_contract_origin');
const {adminConfirmMerchantContractHandler} = require('../merchant_contract_confirm');
const payment = require('../merchant_contract_payment');
const outbox = require('../merchant_contract_outbox');

const {db, admin} = h;
const {Timestamp} = admin.firestore;
let sent;

const allPass = Object.fromEntries(['siret', 'identity', 'activity', 'duplicate', 'offer', 'origin', 'cgv', 'fraud']
  .map((name) => [name, {result: 'pass'}]));

async function confirmedContract(overrides = {}, {merchant = 'merchant', enseigne = 'e1'} = {}) {
  const {contractId} = await submitMerchantSubscriptionRequestHandler({
    enseigneId: enseigne, siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true, ...overrides,
  }, h.merchantContext(merchant));
  const {stateVersion} = await review.adminRecordMerchantContractChecksHandler({contractId, expectedVersion: 1, checks: allPass}, h.adminContext());
  const result = await adminConfirmMerchantContractHandler({contractId, expectedVersion: stateVersion}, h.adminContext());
  return {contractId, result};
}

const tokenFrom = (message) => /paiement=([A-Za-z0-9_-]+)/.exec(message.text)?.[1];
const contract = async (id) => (await db.doc(`merchant_contracts/${id}`).get()).data();

test.beforeEach(async () => {
  await h.clearFirestore();
  await h.setConfig();
  await h.seedMerchant('merchant');
  await h.seedMerchant('other');
  await h.seedAdmin('admin');
  await h.seedEnseigne('e1', 'merchant');
  await h.seedEnseigne('e2', 'merchant');
  sent = h.captureMail(mail);
  cgvDocument.setLoader(async () => h.kCgvBytes);
});
test.after(() => {
  mail.setSender(null);
  cgvDocument.setLoader(null);
});

test('expiration : fin du 15e jour suivant l\'envoi, heure de Paris (changement d\'heure compris)', () => {
  assert.equal(new Date(payment.paymentLinkExpiry(Date.UTC(2026, 2, 20, 9))).toISOString(), '2026-04-04T21:59:59.999Z');
  assert.equal(new Date(payment.paymentLinkExpiry(Date.UTC(2026, 11, 1, 22, 30))).toISOString(), '2026-12-16T22:59:59.999Z');
});

test('spontanee : invitation envoyee avec la confirmation, jeton stocke en empreinte seulement, dates a l\'envoi', async () => {
  const {contractId, result} = await confirmedContract();
  assert.equal(result.invitation, 'sent');
  const invitation = sent.find((m) => /invitation à régler/.test(m.subject));
  assert.ok(invitation);
  const token = tokenFrom(invitation);
  assert.ok(token && token.length >= 40);
  assert.match(invitation.text, /https:\/\/www\.proxiplay\.fr\/espace-commercant\/\?paiement=/);
  assert.doesNotMatch(invitation.text, /checkout\.stripe\.com|buy\.stripe\.com/, 'jamais un lien de paiement Stripe');
  const tokens = await db.collection('payment_tokens').get();
  assert.deepEqual(tokens.docs.map((d) => d.id), [payment.hashToken(token)]);
  assert.ok(!JSON.stringify(tokens.docs[0].data()).includes(token));
  const c = await contract(contractId);
  const sentAt = tokens.docs[0].data().sent_at.toMillis();
  assert.equal(c.payment_invited_at.toMillis(), sentAt);
  assert.equal(c.payment_link_expires_at.toMillis(), payment.paymentLinkExpiry(sentAt));
  assert.equal(tokens.docs[0].data().expires_at.toMillis(), c.payment_link_expires_at.toMillis());
  assert.match(invitation.text, /valable jusqu'au .* inclus \(quinze jours, CGV art\. 8\.1\)/);
});

test('page de paiement : recapitulatif pour le proprietaire seulement ; lien inconnu ou d\'un autre compte indiscernables', async () => {
  const {contractId} = await confirmedContract();
  const token = tokenFrom(sent.find((m) => /invitation/.test(m.subject)));
  const view = await payment.getPaymentInvitationHandler({token}, h.merchantContext());
  assert.equal(view.contractId, contractId);
  assert.equal(view.offer.first_year_ttc_cents, 43800);
  assert.ok(view.expiresAt > Date.now());
  await h.rejectsWith(payment.getPaymentInvitationHandler({token}, h.merchantContext('other')), 'token_unknown');
  await h.rejectsWith(payment.getPaymentInvitationHandler({token: 'x'.repeat(43)}, h.merchantContext()), 'token_unknown');
  await h.rejectsWith(payment.getPaymentInvitationHandler({token: '../'}, h.merchantContext()), 'token_unknown');
});

test('renvoi admin : ancien lien revoque, nouveau lien, meme date d\'expiration', async () => {
  const {contractId} = await confirmedContract();
  const first = tokenFrom(sent.find((m) => /invitation/.test(m.subject)));
  const expiry = (await contract(contractId)).payment_link_expires_at.toMillis();
  sent.length = 0;
  await payment.adminSendPaymentInvitationHandler({contractId}, h.adminContext());
  const second = tokenFrom(sent[0]);
  assert.notEqual(first, second);
  await h.rejectsWith(payment.getPaymentInvitationHandler({token: first}, h.merchantContext()), 'token_revoked');
  assert.equal((await payment.getPaymentInvitationHandler({token: second}, h.merchantContext())).expiresAt, expiry);
  assert.equal((await contract(contractId)).payment_link_expires_at.toMillis(), expiry);
  await h.rejectsWith(payment.adminSendPaymentInvitationHandler({contractId}, h.merchantContext()), 'permission-denied');
});

test('lien expire : refuse ; contrat qui n\'attend plus de paiement : refuse', async () => {
  const {contractId} = await confirmedContract();
  const token = tokenFrom(sent.find((m) => /invitation/.test(m.subject)));
  await db.doc(`payment_tokens/${payment.hashToken(token)}`).update({expires_at: Timestamp.fromMillis(Date.now() - 1000)});
  await h.rejectsWith(payment.getPaymentInvitationHandler({token}, h.merchantContext()), 'token_expired');
  await db.doc(`payment_tokens/${payment.hashToken(token)}`).update({expires_at: Timestamp.fromMillis(Date.now() + 86400000)});
  await db.doc(`merchant_contracts/${contractId}`).update({state: 'active'});
  await h.rejectsWith(payment.getPaymentInvitationHandler({token}, h.merchantContext()), 'already_paid');
  await db.doc(`merchant_contracts/${contractId}`).update({state: 'withdrawn'});
  await h.rejectsWith(payment.getPaymentInvitationHandler({token}, h.merchantContext()), 'not_payment_invited');
});

test('demarchee : aucune invitation avant la fin du delai de retractation ; apres, invitation', async () => {
  const {contractId, result} = await confirmedContract({visitDeclared: true});
  assert.equal(result.state, 'withdrawal_pending');
  assert.equal((await db.collection('payment_tokens').get()).size, 0);
  await h.rejectsWith(payment.adminSendPaymentInvitationHandler({contractId}, h.adminContext()), 'withdrawal_period_running');
  await db.doc(`merchant_contracts/${contractId}`).update({withdrawal_deadline: Timestamp.fromMillis(Date.now() - 1000)});
  sent.length = 0;
  const outcome = await payment.adminSendPaymentInvitationHandler({contractId}, h.adminContext());
  assert.equal(outcome.sent, true);
  assert.equal((await contract(contractId)).state, 'payment_invited');
  assert.equal(sent.length, 1);
});

test('visite signalee pendant l\'attente du paiement : retour au delai de retractation, liens revoques', async () => {
  const {contractId} = await confirmedContract();
  const token = tokenFrom(sent.find((m) => /invitation/.test(m.subject)));
  await origin.reportMerchantVisitHandler({contractId}, h.merchantContext());
  const c = await contract(contractId);
  assert.equal(c.state, 'withdrawal_pending');
  assert.equal(c.origin.type, 'demarchee');
  assert.equal(c.payment_link_expires_at, null);
  assert.ok((await db.doc(`payment_tokens/${payment.hashToken(token)}`).get()).data().revoked_at);
  await h.rejectsWith(payment.getPaymentInvitationHandler({token}, h.merchantContext()), 'not_payment_invited');
});

test('SMTP en panne a l\'invitation : contrat conclu, jeton jamais remis revoque, file de reprise, alerte admin ; reprise', async () => {
  const {contractId: id0} = await (async () => {
    const {contractId} = await submitMerchantSubscriptionRequestHandler({
      enseigneId: 'e1', siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
      cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
    }, h.merchantContext());
    return {contractId};
  })();
  const {stateVersion} = await review.adminRecordMerchantContractChecksHandler({contractId: id0, expectedVersion: 1, checks: allPass}, h.adminContext());
  // La confirmation part, l'invitation echoue.
  let calls = 0;
  mail.setSender(async (message) => {
    calls += 1;
    if (/invitation à régler|Alerte/.test(message.subject)) throw new Error('smtp indisponible (test)');
    return {messageId: `<m${calls}@test>`};
  });
  const result = await adminConfirmMerchantContractHandler({contractId: id0, expectedVersion: stateVersion}, h.adminContext());
  assert.equal(result.state, 'payment_invited');
  assert.equal(result.invitation, 'queued');
  const c = await contract(id0);
  assert.equal(c.payment_invited_at, undefined, 'aucune date : rien n\'est parti');
  const tokens = await db.collection('payment_tokens').get();
  assert.ok(tokens.docs.every((d) => d.data().revoked_at), 'jeton jamais remis : revoque');
  const queued = await db.collection('mail_outbox').get();
  assert.equal(queued.size, 1);
  assert.equal(queued.docs[0].data().kind, 'payment_invitation');
  assert.equal(queued.docs[0].data().message, null, 'aucun jeton en clair dans la file');
  const alerts = await db.collection('admin_alerts').get();
  assert.equal(alerts.size, 1);
  assert.equal(alerts.docs[0].data().kind, 'email_echec');
  // Reprise apres le delai : nouvelle invitation, dates fixees a l'envoi effectif.
  sent = h.captureMail(mail);
  const stats = await mail.runMailOutbox({nowMs: Date.now() + 16 * 60 * 1000});
  assert.equal(stats.sent, 1);
  assert.equal(sent.length, 1);
  const after = await contract(id0);
  assert.ok(after.payment_invited_at);
  assert.equal(after.payment_link_expires_at.toMillis(), payment.paymentLinkExpiry(after.payment_invited_at.toMillis()));
  const token = tokenFrom(sent[0]);
  assert.equal((await payment.getPaymentInvitationHandler({token}, h.merchantContext())).contractId, id0);
  assert.equal((await db.collection('mail_outbox').get()).docs[0].data().status, 'sent');
});

test('file de reprise : message texte rejoue ; apres 5 tentatives, abandon et alerte « action manuelle »', async () => {
  h.captureMail(mail, {fail: true});
  const {contractId} = await submitMerchantSubscriptionRequestHandler({
    enseigneId: 'e1', siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
  }, h.merchantContext());
  const entries = await db.collection('mail_outbox').where('contract_id', '==', contractId).get();
  assert.deepEqual(entries.docs.map((d) => d.data().key).sort(), ['admin_new_request', 'request_ack']);
  let now = Date.now();
  for (let i = 0; i < 4; i++) {
    now += 7 * 3600 * 1000;
    await mail.runMailOutbox({nowMs: now});
  }
  const statuses = (await db.collection('mail_outbox').get()).docs.map((d) => [d.data().status, d.data().attempts]);
  assert.deepEqual(statuses, [['failed', 5], ['failed', 5]]);
  const abandoned = await db.collection('admin_alerts').where('kind', '==', 'email_abandonne').get();
  assert.equal(abandoned.size, 2);
  // Relance manuelle par l'admin, SMTP retabli.
  sent = h.captureMail(mail);
  const target = (await db.collection('mail_outbox').where('key', '==', 'request_ack').get()).docs[0];
  await outbox.adminRetryMailOutboxHandler({outboxId: target.id}, h.adminContext());
  await mail.runMailOutbox({nowMs: Date.now() + 1000});
  assert.equal(sent.length, 1);
  assert.match(sent[0].subject, /bien reçu votre demande/);
  assert.equal((await target.ref.get()).data().status, 'sent');
  assert.ok((await db.doc(`merchant_contracts/${contractId}/internal/record`).get()).data().emails.request_ack.sent_at);
});

test('file de reprise : pas de double envoi par deux executions simultanees ; actions admin reservees', async () => {
  h.captureMail(mail, {fail: true});
  await submitMerchantSubscriptionRequestHandler({
    enseigneId: 'e1', siret: '98896837600018', raisonSociale: 'PROXIPLAY TEST SAS', offerId: 'autonome',
    cgvAccepted: true, cgvVersion: h.kCgv.version, cgvSha256: h.kCgvSha256, jurisdictionClauseAccepted: true,
  }, h.merchantContext());
  sent = h.captureMail(mail);
  const later = Date.now() + 16 * 60 * 1000;
  await Promise.all([mail.runMailOutbox({nowMs: later}), mail.runMailOutbox({nowMs: later})]);
  assert.equal(sent.length, 2, 'deux entrees, chacune envoyee une fois');
  const any = (await db.collection('mail_outbox').get()).docs[0].id;
  await h.rejectsWith(outbox.adminRetryMailOutboxHandler({outboxId: any}, h.merchantContext()), 'permission-denied');
  await h.rejectsWith(outbox.adminAbandonMailOutboxHandler({outboxId: any}, h.merchantContext()), 'permission-denied');
  const alert = (await db.collection('admin_alerts').get()).docs[0].id;
  await outbox.adminResolveAlertHandler({alertId: alert}, h.adminContext());
  assert.equal((await db.doc(`admin_alerts/${alert}`).get()).data().resolved, true);
});

test('delai de retractation : meme date que le signalement (fin du 14e jour, Paris)', async () => {
  const {contractId} = await confirmedContract({visitDeclared: true});
  const c = await contract(contractId);
  assert.equal(c.withdrawal_deadline.toMillis(), paris.visitReportDeadline(c.confirmed_at.toMillis()));
});
