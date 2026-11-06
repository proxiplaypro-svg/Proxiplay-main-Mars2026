const test = require('node:test');
const assert = require('node:assert/strict');
const {
  isMarketingEmailRecipient,
  filterMarketingEmailRecipients,
} = require('../lib/marketing_consent_recipients');

test('only an explicit, age-eligible consent is a marketing recipient', () => {
  assert.equal(isMarketingEmailRecipient({}), false);
  assert.equal(isMarketingEmailRecipient({marketing_consent: {enabled: false}}), false);
  assert.equal(isMarketingEmailRecipient({marketing_consent: {enabled: true}}), false);
  assert.equal(isMarketingEmailRecipient({marketing_consent: {
    enabled: true,
    newsletter_eligibility: 'age_15_plus_confirmed',
  }}), true);
});

test('the future campaign filter excludes unknown and withdrawn choices', () => {
  const recipients = filterMarketingEmailRecipients([
    {email: 'unknown@example.test'},
    {email: 'withdrawn@example.test', marketing_consent: {enabled: false}},
    {email: 'eligible@example.test', marketing_consent: {
      enabled: true,
      newsletter_eligibility: 'age_15_plus_confirmed',
    }},
  ]);
  assert.deepEqual(recipients.map(({email}) => email), ['eligible@example.test']);
});
