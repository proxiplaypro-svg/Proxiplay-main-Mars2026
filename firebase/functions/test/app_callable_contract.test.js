// Contract between the Flutter app and this codebase: every callable the app
// invokes by name must be exported here, otherwise a full deploy would remove
// it (or it was never deployed) and the app would get "not-found".
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-proxiplay-callable-contract';
process.env.FIREBASE_CONFIG = process.env.FIREBASE_CONFIG || JSON.stringify({projectId: process.env.GCLOUD_PROJECT});

// Called only from the legacy in-app admin page and served by a function
// deployed from an older source; kept visible here rather than silently ignored.
const KNOWN_LEGACY = new Set(['unlockCommercantAccount']);

function dartFiles(dir) {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(e => {
    const p = path.join(dir, e.name);
    return e.isDirectory() ? dartFiles(p) : e.name.endsWith('.dart') ? [p] : [];
  });
}

function appCallables() {
  const names = new Set();
  const pattern = /(?:httpsCallable|makeCloudCall|_call)\(\s*['"]([A-Za-z0-9_]+)['"]/g;
  for (const file of dartFiles(path.join(__dirname, '..', '..', '..', 'lib'))) {
    for (const m of fs.readFileSync(file, 'utf8').matchAll(pattern)) names.add(m[1]);
  }
  return names;
}

function exportedFunctions() {
  const out = new Set();
  const walk = (obj, prefix) => {
    for (const [k, v] of Object.entries(obj)) {
      if (v && v.__endpoint) out.add(prefix + k);
      else if (v && typeof v === 'object' && !Array.isArray(v)) walk(v, prefix + k + '-');
    }
  };
  walk(require('../index'), '');
  return out;
}

test('every callable used by the app is exported by the functions codebase', () => {
  const calls = appCallables();
  assert.ok(calls.size > 20, 'callable scan found too few names: ' + calls.size);
  const exported = exportedFunctions();
  const missing = [...calls].filter(n => !exported.has(n) && !KNOWN_LEGACY.has(n)).sort();
  assert.deepEqual(missing, []);
});

test('the referral e-mail signup callable used by 1.1.2 is exported', () => {
  assert.ok(appCallables().has('createReferralEmailAccount'));
  assert.ok(exportedFunctions().has('createReferralEmailAccount'));
});

test('legacy allowances stay justified: each one is still called by the app', () => {
  const calls = appCallables();
  for (const name of KNOWN_LEGACY) assert.ok(calls.has(name), name + ' no longer called: remove it from KNOWN_LEGACY');
});
