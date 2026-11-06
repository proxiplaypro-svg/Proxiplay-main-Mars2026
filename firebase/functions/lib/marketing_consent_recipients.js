// The only eligibility predicate future commercial campaigns may use.
// Service messages intentionally do not import this module.
function isMarketingEmailRecipient(user = {}) {
  const consent = user && user.marketing_consent;
  return consent?.enabled === true &&
    consent?.newsletter_eligibility === 'age_15_plus_confirmed';
}

function filterMarketingEmailRecipients(users = []) {
  return users.filter(isMarketingEmailRecipient);
}

module.exports = {isMarketingEmailRecipient, filterMarketingEmailRecipients};
