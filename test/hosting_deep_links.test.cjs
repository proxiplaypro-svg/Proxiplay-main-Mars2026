// Hosting deep links (1.1.2, step 5): French App Store storefront everywhere,
// the referral page /i, the app association files and the Hosting config
// (rewrites, redirects to www.proxiplay.fr, headers) kept as live.
// Run: node --test test/hosting_deep_links.test.cjs (from the repo root).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const kFrenchAppStore = 'https://apps.apple.com/fr/app/proxiplay/id6753818573';
const htmlFiles = (dir) => fs.readdirSync(dir, {withFileTypes: true}).flatMap((e) =>
  e.isDirectory() ? htmlFiles(path.join(dir, e.name)) : e.name.endsWith('.html') ? [path.join(dir, e.name)] : []);

test('every App Store link of the Hosting pages is the French storefront', () => {
  const found = [];
  for (const file of htmlFiles('hosting')) {
    for (const [url] of fs.readFileSync(file, 'utf8').matchAll(/https:\/\/apps\.apple\.com\/[^"'\s)]*/g)) {
      found.push(file);
      assert.equal(url, kFrenchAppStore, file);
    }
  }
  for (const page of ['i', 'j', 'app']) {
    assert.ok(found.some((f) => f.includes(path.join('hosting', page, 'index.html'))), page);
  }
});

function runReferralPage(userAgent, search) {
  const html = fs.readFileSync('hosting/i/index.html', 'utf8');
  const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1])
    .find((s) => s.includes("get('ref')"));
  assert.ok(script);
  const elements = new Map();
  const element = (id) => {
    if (!elements.has(id)) elements.set(id, {href: '', textContent: '', hidden: true, addEventListener() {}});
    return elements.get(id);
  };
  vm.runInNewContext(script, {
    window: {location: {search}, isSecureContext: true},
    navigator: {userAgent},
    document: {getElementById: element},
    URLSearchParams, encodeURIComponent,
  });
  return element;
}

test('/i: a valid code opens the app (Android intent with Play Store fallback, iOS scheme)', () => {
  const android = runReferralPage('Mozilla/5.0 (Linux; Android 14)', '?ref=418ba725');
  assert.equal(android('code').textContent, '418BA725');
  assert.equal(android('with-code').hidden, false);
  const intent = android('open-app').href;
  assert.ok(intent.startsWith('intent://proxiplay.com/i?ref=418BA725#Intent;scheme=proxiplay;package=com.proxiplay.proxiplay;'));
  // The store fallback keeps the code as the install referrer (encoded once).
  assert.match(decodeURIComponent(intent), /S\.browser_fallback_url=https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.proxiplay\.proxiplay&referrer=ref%3D418BA725;end$/);
  assert.equal(android('play-store').href,
    'https://play.google.com/store/apps/details?id=com.proxiplay.proxiplay&referrer=' + encodeURIComponent('ref=418BA725'));
  const iphone = runReferralPage('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0)', '?ref=418BA725');
  assert.equal(iphone('open-app').href, 'proxiplay://proxiplay.com/i?ref=418BA725');
});

test('/i: an invalid or missing code shows nothing to open', () => {
  for (const search of ['', '?ref=', '?ref=%3Cscript%3E', '?ref=TEST', '?ref=12']) {
    const page = runReferralPage('Android', search);
    assert.equal(page('with-code').hidden, true, search);
    assert.equal(page('open-app').href, '', search);
  }
});

test('app association files: iOS /j/* and /i, Android package with signing fingerprints', () => {
  const aasa = JSON.parse(fs.readFileSync('hosting/.well-known/apple-app-site-association', 'utf8'));
  const detail = aasa.applinks.details[0];
  assert.equal(detail.appID, '9FBNDYD396.com.proxiplay.proxiplay');
  assert.deepEqual(detail.paths, ['/j/*', '/i']);
  const links = JSON.parse(fs.readFileSync('hosting/.well-known/assetlinks.json', 'utf8'));
  const target = links[0].target;
  assert.equal(target.package_name, 'com.proxiplay.proxiplay');
  assert.ok(target.sha256_cert_fingerprints.length >= 1);
  assert.deepEqual(links[0].relation, ['delegate_permission/common.handle_all_urls']);
});

test('Hosting config keeps the live routes: pages, redirects to the showcase site, headers', () => {
  const hosting = JSON.parse(fs.readFileSync('firebase.json', 'utf8')).hosting;
  assert.deepEqual(hosting.rewrites, [
    {source: '/app/**', destination: '/app/index.html'},
    {source: '/j/**', destination: '/j/index.html'},
    {source: '/i', destination: '/i/index.html'},
  ]);
  assert.deepEqual(hosting.redirects, [
    {source: '/', destination: 'https://www.proxiplay.fr/', type: 301},
    {source: '/legal.html', destination: 'https://www.proxiplay.fr/legal.html', type: 301},
    {source: '/suppression-compte/**', destination: 'https://www.proxiplay.fr/suppression-compte.html', type: 301},
  ]);
  assert.deepEqual(hosting.headers.map((h) => h.source).sort(),
    ['/.well-known/apple-app-site-association', '/.well-known/assetlinks.json']);
  for (const h of hosting.headers) assert.deepEqual(h.headers, [{key: 'Content-Type', value: 'application/json'}]);
});
