const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const cases = [
  ['classic with no parameters', ''],
  ['merchant parameters', '?merchantId=285z9Tnwy8TgtIl8pR8D&merchant_id=285z9Tnwy8TgtIl8pR8D'],
  ['secure token and repeated parameters', '?qr_token=' + 'a'.repeat(64) + '&animation_id=a&x=1&x=2'],
];

for (const page of ['hosting/j/index.html', 'hosting/app/index.html']) {
  for (const platform of ['Android', 'iPhone']) {
    for (const [description, query] of cases) {
      test(page + ' ' + platform + ': ' + description, () => {
        const html = fs.readFileSync(page, 'utf8');
        const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]).find(s => s.includes('qr-open-app'));
        assert.ok(script);
        const elements = new Map();
        const element = id => {
          if (!elements.has(id)) elements.set(id, { href: '', textContent: '', classList: { add() {} }, addEventListener(event, fn) { this[event] = fn; } });
          return elements.get(id);
        };
        const messages = [];
        const timers = [];
        const window = { location: { pathname: '/j/nGpCJUpqvqbP0EfwU0Hk', search: query, href: '' }, addEventListener() {}, setTimeout: fn => timers.push(fn) };
        const context = { window, navigator: { userAgent: platform }, document: { getElementById: element, addEventListener() {} }, console: { log: (...args) => messages.push(args.join(' ')) }, setTimeout: fn => timers.push(fn), encodeURIComponent };
        vm.runInNewContext(script, context);
        const link = element('qr-open-app').href;
        const prefix = platform === 'Android' ? 'intent://game/' : 'proxiplay://game/';
        assert.ok(link.startsWith(prefix + 'nGpCJUpqvqbP0EfwU0Hk' + query));
        if (platform === 'Android') {
          assert.match(link, /#Intent;scheme=proxiplay;package=com\.proxiplay\.proxiplay;/);
          assert.match(decodeURIComponent(link), /S\.browser_fallback_url=https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.proxiplay\.proxiplay/);
        }
        const storeId = page === 'hosting/j/index.html' ? 'qr-open-store' : platform === 'Android' ? 'qr-open-android' : 'qr-open-ios';
        assert.match(element(storeId).href, platform === 'Android' ? /play\.google\.com/ : /apps\.apple\.com/);
        element('qr-open-app').click({ preventDefault() {} });
        assert.equal(window.location.href, link);
        for (const timer of timers.slice(0, 1)) timer();
        assert.ok(!messages.join(' ').includes('a'.repeat(64)));
      });
    }
  }
}
