#!/usr/bin/env python3
"""Fixture-driven tests for the pure parts of 1977.news.

NewsModel.js is ordinary JavaScript; the host shell evaluates it inside QML,
while these checks run the same file under node so fail/non-running-fixture
behavior is provable without a live shell. Qt and Quickshell APIs never enter
this file by design.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

JUICE = r"""
const M = require(process.argv[2])
const fixture = JSON.parse(require('fs').readFileSync(process.argv[3], 'utf8'))
const j = JSON.stringify
let failures = 0

function check(name, actual, expected) {
  if (j(actual) !== j(expected)) {
    process.stderr.write(`FAIL ${name}\n  got: ${j(actual)}\n  want: ${j(expected)}\n`)
    failures++
  }
}

// ---- atom parsing
const items = M.atomToItems(fixture.omarchyAtom, 'omarchy')
check('omarchy: item count', items.length, 2)
check('omarchy: first id', items[0].id, 'tag:github.com,2008:Repository/1/v4.0.5')
check('omarchy: first title', items[0].title, 'v4.0.5')
check('omarchy: first link', items[0].link, 'https://github.com/omacom/omarchy/releases/tag/v4.0.5')
if (!(items[0].updatedMs > 0)) { process.stderr.write('FAIL omarchy updatedMs\n'); failures++ }
check('omarchy: entity decode', M.decodeEntities(fixture.entityIn), '<a> & "b"')

// ---- marketplace commit feed parses into new-plugin news
const mp = M.atomToItems(fixture.marketplaceAtom, 'marketplace')
check('marketplace count', mp.length, 2)
check('marketplace new plugin', mp[1].title, 'New plugin: Luddite Scout')
check('marketplace omamail', mp[0].title, 'New plugin: Omamail')

// ---- canary and settings filtering
const filtered = M.applySettings(fixture.rawItems, { filterCanary: true })
check('canary filtered', filtered.map(i => i.id), ['idh', 'ido'])
check('canary kept', M.applySettings(fixture.rawItems, { filterCanary: false }).map(i => i.id).length, 3)
check('source off', M.applySettings(fixture.rawItems, { sourceHermes: false }).map(i => i.id), ['ido'])
check('old entries dropped', M.applySettings(fixture.rawItems, {}).map(i => i.id).includes('ido-old'), false)
const many = Array.from({ length: 25 }, (_, i) => ({ id: 'x' + i, source: 'opencode', updatedMs: 1792200000000 + i * 1000 }))
check('maxItems cap', M.applySettings(many, { maxItems: 20 }).length, 20)
check('min clamp', M.applySettings(many, { maxItems: 1 }).length, 20)
check('clamped maxItems', M.coerceInt('x', 80, 20, 200), 80)

// ---- dedupe and unread
check('dedupe', M.dedupe([{ id: 'a' }, { id: 'a' }, { id: 'b' }]).length, 2)
check('unread empty read', M.unreadCount([{ id: 'a' }, { id: 'b' }], {}), 2)
check('unread mark a', M.unreadCount([{ id: 'a' }, { id: 'b' }], { a: 1 }), 1)

// ---- seen-state persistence is bounded and forgiving
check('normalize garbage', M.normalizeSeen('[broken').read, {})
const merged = M.mergeSeen({}, ['x'], 5)
check('merge seen', merged, { x: 5 })
const full = {};
for (let i = 0; i < M.MAX_SEEN + 50; i++) full['key-' + i] = i
check('seen bounded', Object.keys(M.mergeSeen(full, ['late'])).length, M.MAX_SEEN)

// ---- links only open inside our allowlist
check('safe link', M.safeLink({ link: 'https://github.com/omacom/omarchy/releases/tag/v4.0.5' }),
  'https://github.com/omacom/omarchy/releases/tag/v4.0.5')
check('unsafe scheme', M.safeLink({ link: 'file:///etc/passwd' }), '')
check('unsafe host', M.safeLink({ link: 'https://evil.example/x' }), '')

// ---- bounded status text
check('bound error', M.boundErrorText('Publish'.repeat(200)).length, 120)

// ---- error bound on titles
check('title cap', M.atomToItems(fixture.longTitleAtom, 'omarchy')[0].title.length <= 120, true)

process.exit(failures ? 1 : 0)
"""

def run_node():
    import shutil
    if shutil.which("node") is None:
        return "node unavailable, NewsModel.js fixture checks skipped", 0
    fixtures = ROOT / "demo" / "fixtures" / "news.json"
    if not fixtures.exists():
        return "missing fixture demo/fixtures/news.json", 1
    script = ROOT / ".testnews.js"
    script.write_text(JUICE)
    proc = subprocess.run(
        ["node", str(script), str(ROOT / "NewsModel.js"), str(fixtures)],
        capture_output=True, text=True, cwd=str(ROOT),
    )
    script.unlink()
    return proc.stderr or proc.stdout, proc.returncode

if __name__ == "__main__":
    out, code = run_node()
    if out.strip():
        print(out.strip())
    print("news model fixture checks", "passed" if code == 0 else "FAILED")
    raise SystemExit(code)
