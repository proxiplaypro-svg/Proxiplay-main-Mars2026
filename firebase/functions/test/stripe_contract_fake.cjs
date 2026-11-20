// Double du SDK Stripe pour les tests de la tranche 2a : aucun reseau, aucune
// cle. Objets en mode test (livemode: false), comme sur un projet demo-.
// Simule les appels utilises par les lots 1.7, 1.8 et 1.5, et permet de
// declencher un paiement (complete) pour fabriquer les evenements du webhook.

process.env.STRIPE_PRICE_AUTONOME ||= 'price_test_autonome';
process.env.STRIPE_PRICE_ACCOMPAGNEE ||= 'price_test_accompagnee';
process.env.STRIPE_TAX_MODE ||= 'tax_rate';
process.env.STRIPE_TAX_RATE_ID ||= 'txr_test_fixture';

const kApiVersionPayload = '2026-10-28.endive';

function catalogPrices() {
  const base = {active: true, currency: 'eur', type: 'recurring', recurring: {interval: 'year', interval_count: 1},
    tax_behavior: 'exclusive', livemode: false};
  return {
    price_test_autonome: {...base, id: 'price_test_autonome', unit_amount: 36500},
    price_test_accompagnee: {...base, id: 'price_test_accompagnee', unit_amount: 100000},
  };
}

function makeContractStripe({prices = catalogPrices(), taxRate = null, upcomingOverride = null} = {}) {
  const rate = taxRate || {id: 'txr_test_fixture', active: true, inclusive: false, percentage: 20, livemode: false};
  const calls = {customersCreate: [], couponsCreate: [], sessionsCreate: [], sessionsExpire: [], upcoming: [],
    refundsCreate: [], creditNotesCreate: [], subscriptionsCancel: [], invoicesVoid: [],
    invoicesUpdate: [], invoicesFinalize: [], subscriptionsUpdate: []};
  // Lot 1.12 : crochets de course (ex. prelevement entre la finalisation et le void).
  const hooks = {afterFinalize: null, beforeVoid: null};
  const store = {customers: {}, coupons: {}, sessions: {}, subscriptions: {}, invoices: {}, charges: {}, idem: {}};
  let n = 0;
  const id = (prefix) => `${prefix}_test_${++n}`;
  const idem = (options, make) => {
    const key = options?.idempotencyKey;
    if (key && store.idem[key]) return store.idem[key];
    const created = make();
    if (key) store.idem[key] = created;
    return created;
  };
  const err = (code, message) => Object.assign(new Error(message), {type: 'StripeInvalidRequestError', code});

  const stripe = {
    calls, store,
    prices: {retrieve: async (priceId) => prices[priceId] || null},
    taxRates: {retrieve: async (rateId) => (rateId === rate.id ? rate : null)},
    customers: {
      create: async (params, options) => idem(options, () => {
        calls.customersCreate.push({params, options});
        const customer = {id: id('cus'), livemode: false, ...params};
        store.customers[customer.id] = customer;
        return customer;
      }),
      retrieve: async (customerId) => store.customers[customerId] || {id: customerId, livemode: false, metadata: {}},
    },
    coupons: {
      create: async (params, options) => idem(options, () => {
        calls.couponsCreate.push({params, options});
        const coupon = {id: id('coupon'), valid: true, livemode: false, ...params};
        store.coupons[coupon.id] = coupon;
        return coupon;
      }),
      retrieve: async (couponId) => store.coupons[couponId] || null,
    },
    invoices: {
      retrieveUpcoming: async (params) => {
        calls.upcoming.push(params);
        if (upcomingOverride) return upcomingOverride(params);
        const item = params.subscription_items[0];
        const price = prices[item.price];
        const coupon = params.discounts?.[0]?.coupon ? store.coupons[params.discounts[0].coupon] : null;
        const net = price.unit_amount - (coupon?.amount_off || 0);
        const tax = item.tax_rates?.length ? Math.round(net * rate.percentage / 100) : 0;
        return {currency: 'eur', total_excluding_tax: net, tax, total: net + tax, subtotal: price.unit_amount};
      },
      retrieve: async (invoiceId) => store.invoices[invoiceId] || null,
      list: async ({subscription}) => ({data: Object.values(store.invoices).filter((i) => i.subscription === subscription)}),
      voidInvoice: async (invoiceId, params, options) => {
        calls.invoicesVoid.push(invoiceId);
        const invoice = store.invoices[invoiceId];
        if (hooks.beforeVoid) hooks.beforeVoid(invoice);
        // Comme Stripe (essai du 2026-11-20) : refus d'une facture payee avec un code VIDE.
        if (invoice.status === 'paid') throw err(null, 'Invoices with `paid` payments cannot be voided.');
        if (invoice.status !== 'open') throw err('invoice_not_open', 'not open');
        invoice.status = 'void';
        return invoice;
      },
      update: async (invoiceId, params, options) => {
        calls.invoicesUpdate.push({invoiceId, params, options});
        Object.assign(store.invoices[invoiceId], params);
        return store.invoices[invoiceId];
      },
      finalizeInvoice: async (invoiceId, params, options) => {
        calls.invoicesFinalize.push({invoiceId, params, options});
        const invoice = store.invoices[invoiceId];
        if (invoice.status !== 'draft') throw err('invoice_not_draft', 'not draft');
        invoice.status = 'open';
        if (params?.auto_advance === false) invoice.auto_advance = false;
        if (hooks.afterFinalize) hooks.afterFinalize(invoice);
        return invoice;
      },
    },
    checkout: {sessions: {
      create: async (params, options) => idem(options, () => {
        calls.sessionsCreate.push({params, options});
        const sessionId = id('cs');
        const session = {id: sessionId, object: 'checkout.session', url: `https://checkout.stripe.com/c/pay/${sessionId}`,
          status: 'open', payment_status: 'unpaid', mode: params.mode, livemode: false, customer: params.customer,
          client_reference_id: params.client_reference_id, metadata: params.metadata, expires_at: params.expires_at,
          subscription: null, _params: params};
        store.sessions[sessionId] = session;
        return session;
      }),
      retrieve: async (sessionId) => store.sessions[sessionId] || null,
      expire: async (sessionId) => {
        calls.sessionsExpire.push(sessionId);
        const session = store.sessions[sessionId];
        if (session.status !== 'open') throw err('checkout_session_not_open', 'not open');
        session.status = 'expired';
        return session;
      },
    }},
    subscriptions: {
      retrieve: async (subscriptionId) => store.subscriptions[subscriptionId] || null,
      update: async (subscriptionId, params, options) => idem(options, () => {
        calls.subscriptionsUpdate.push({subscriptionId, params, options});
        Object.assign(store.subscriptions[subscriptionId], params);
        return store.subscriptions[subscriptionId];
      }),
      cancel: async (subscriptionId, params, options) => idem(options, () => {
        calls.subscriptionsCancel.push({subscriptionId, params, options});
        const sub = store.subscriptions[subscriptionId];
        sub.status = 'canceled';
        sub.canceled_at = Math.floor(Date.now() / 1000);
        sub.ended_at = sub.canceled_at;
        return sub;
      }),
    },
    refunds: {create: async (params, options) => idem(options, () => {
      calls.refundsCreate.push({params, options});
      return {id: id('re'), status: 'succeeded', livemode: false, ...params};
    })},
    creditNotes: {create: async (params, options) => idem(options, () => {
      calls.creditNotesCreate.push({params, options});
      return {id: id('cn'), status: 'issued', livemode: false, refund: id('re'), ...params};
    })},
    charges: {retrieve: async (chargeId) => store.charges[chargeId] || null},
  };

  /** Simule le paiement d'une session : abonnement, facture payee, charge. */
  stripe.complete = (sessionId, {nowSeconds = Math.floor(Date.now() / 1000), status = 'active'} = {}) => {
    const session = store.sessions[sessionId];
    const p = session._params;
    const subscriptionId = id('sub');
    const invoiceId = id('in');
    const chargeId = id('ch');
    const coupon = p.discounts?.[0]?.coupon ? store.coupons[p.discounts[0].coupon] : null;
    const price = prices[p.line_items[0].price];
    const net = price.unit_amount - (coupon?.amount_off || 0);
    const total = net + (p.line_items[0].tax_rates ? Math.round(net * 0.2) : 0);
    store.subscriptions[subscriptionId] = {
      id: subscriptionId, object: 'subscription', status, livemode: false, customer: session.customer,
      metadata: p.subscription_data.metadata, cancel_at_period_end: false, cancel_at: null, canceled_at: null, ended_at: null,
      latest_invoice: invoiceId,
      items: {data: [{price: {id: price.id}, current_period_start: nowSeconds, current_period_end: nowSeconds + 365 * 86400}]},
      current_period_start: nowSeconds, current_period_end: nowSeconds + 365 * 86400,
    };
    store.invoices[invoiceId] = {id: invoiceId, object: 'invoice', status: 'paid', paid: true, livemode: false,
      subscription: subscriptionId, billing_reason: 'subscription_create', lines: {data: [{period: {start: nowSeconds, end: nowSeconds + 365 * 86400}}]}, amount_paid: total, total, subtotal: price.unit_amount,
      payment_intent: id('pi'), charge: chargeId, status_transitions: {paid_at: nowSeconds}};
    store.charges[chargeId] = {id: chargeId, invoice: invoiceId, amount: total, livemode: false};
    Object.assign(session, {status: 'complete', payment_status: 'paid', subscription: subscriptionId});
    return {subscriptionId, invoiceId, chargeId, total};
  };

  /**
   * Renouvellement : la periode avance, une facture subscription_cycle est
   * creee dans l'etat voulu (draft : dans l'heure ; open : prelevement echoue ;
   * paid : preleve). Renvoie l'identifiant de la facture.
   */
  stripe.renew = (subscriptionId, {status = 'draft', amount = 43800, subscriptionStatus} = {}) => {
    const sub = store.subscriptions[subscriptionId];
    const start = sub.current_period_end;
    const end = start + 365 * 86400;
    const invoiceId = id('in');
    store.invoices[invoiceId] = {id: invoiceId, object: 'invoice', status, paid: status === 'paid', livemode: false,
      subscription: subscriptionId, billing_reason: 'subscription_cycle', amount_paid: status === 'paid' ? amount : 0,
      amount_due: amount, total: amount, payment_intent: id('pi'), attempt_count: status === 'draft' ? 0 : 1,
      period_start: sub.current_period_start, period_end: start,
      lines: {data: [{period: {start, end}}]}, hosted_invoice_url: 'https://invoice.stripe.com/i/test_' + invoiceId,
      status_transitions: status === 'paid' ? {paid_at: start + 3600} : {}};
    Object.assign(sub, {current_period_start: start, current_period_end: end, latest_invoice: invoiceId,
      status: subscriptionStatus || (status === 'open' ? 'past_due' : 'active')});
    sub.items.data[0].current_period_start = start;
    sub.items.data[0].current_period_end = end;
    return invoiceId;
  };
  stripe.hooks = hooks;

  /** Evenement au format de l'endpoint (2026-10-28.endive) : seuls les identifiants comptent. */
  stripe.event = (type, object, {eventId = id('evt'), created = Math.floor(Date.now() / 1000)} = {}) => ({
    id: eventId, type, api_version: kApiVersionPayload, created, livemode: false, data: {object},
  });

  return stripe;
}

module.exports = {makeContractStripe, catalogPrices, kApiVersionPayload};
