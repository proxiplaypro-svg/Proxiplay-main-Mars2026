const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const rulesPath = path.resolve(__dirname, "..", "..", "firestore.rules");
const rules = fs.readFileSync(rulesPath, "utf8");

test("public games-played rule exposes only a direct read and no client writes", () => {
  const match = rules.match(/match\s+\/public_metrics\/games_played\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(match, "public_metrics/games_played rule must exist");
  assert.match(match[1], /allow\s+get:\s*if\s+true/);
  assert.match(match[1], /allow\s+list:\s*if\s+false/);
  assert.match(match[1], /allow\s+create,\s*update,\s*delete:\s*if\s+false/);
});
