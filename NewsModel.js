// Pure parsing and mixing logic for 1977.news. No Qt or Quickshell APIs:
// this file is imported by hosted QML and by tests/run under node.
//
// Item shape travels across the service boundary in one direction only:
//   { id, source, sourceId, title, link, updatedMs }
// `id` is the source's own stable entry id, dedupe is on it, and every
// timestamp is epoch milliseconds (0 when the feed omits it).

var MAX_ITEMS_INPUT = 400
var MAX_TITLE = 120
var MAX_URL = 400
var MAX_ITEM_AGE_DAYS = 90

var SOURCES = {
  omarchy: {
    url: "https://github.com/omacom/omarchy/releases.atom",
    label: "Omarchy",
    chips: ["v", "releases"],
  },
  opencode: {
    url: "https://github.com/anomalyco/opencode/releases.atom",
    label: "OpenCode",
  },
  hermes: {
    url: "https://github.com/NousResearch/Hermes-Agent/releases.atom",
    label: "Hermes",
  },
  marketplace: {
    url: "https://github.com/omacom/omarchy-plugin-marketplace/commits/main/registry.json.atom",
    label: "Marketplace",
  },
}

var ALLOWED_ORIGIN_HOSTS = [
  "github.com",
]

// ---- Atom parsing ----------------------------------------------------------
//
// Tables are scraped with narrow regexes instead of a real XML parser. Only
// the four fixed GitHub feeds above are ever fed through this, and each
// extracted field is bounded and html-escaped at parse time so later display
// can bind it as plain text.

function decodeEntities(text) {
  return String(text || "")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'")
    .replace(/&#0*(\d+);/g, function (_, code) {
      return String.fromCharCode(Number(code))
    })
    .replace(/&amp;/g, "&")
}

function entryTag(entry, tag) {
  var open = entry.indexOf("<" + tag)
  if (open < 0) return ""
  var start = entry.indexOf(">", open) + 1
  var close = entry.indexOf("</" + tag + ">", start)
  if (start < 0 || close < 0) return ""
  return entry.slice(start, close)
}

function entryLink(entry) {
  // Atom link href attribute for the permanent URL of the entry.
  var re = /<link[^>]*rel="alternate"[^>]*href="([^"]+)"[^>]*>/
  var m = entry.match(re)
  if (m && m[1]) return m[1]
  m = entry.match(/<link[^>]*href="([^"]+)"[^>]*rel="alternate"[^>]*>/)
  if (m && m[1]) return m[1]
  m = entry.match(/<link[^>]*href="([^"]+)"[^>]*>/)
  return m && m[1] ? m[1] : ""
}

function parseDateIso8601(text) {
  var t = decodeEntities(text).trim()
  if (!t) return 0
  var ms = Date.parse(t)
  return isNaN(ms) ? 0 : ms
}

function atomToItems(atomText, sourceId) {
  var out = []
  var spec = SOURCES[sourceId] || { label: sourceId }
  var entriesRe = /<entry>([\s\S]*?)<\/entry>/g
  var e
  while ((e = entriesRe.exec(String(atomText || ""))) !== null && out.length < MAX_ITEMS_INPUT) {
    var id = decodeEntities(entryTag(e[1], "id")).trim()
    var title = decodeEntities(entryTag(e[1], "title")).trim()
    if (!id || !title) continue
    var item = {
      id: id.slice(0, MAX_URL),
      source: sourceId,
      sourceLabel: spec.label,
      title: title.slice(0, MAX_TITLE),
      link: entryLink(e[1]).slice(0, MAX_URL),
      updatedMs: parseDateIso8601(entryTag(e[1], "updated")),
    }
    if (sourceId === "marketplace") applyMarketplaceTitle(item, title)
    out.push(item)
  }
  return out
}

function applyMarketplaceTitle(item, rawTitle) {
  // Commit subjects in omarchy-plugin-marketplace read like
  //   "Add Luddite Scout plugin (#12057)" — surface first-refactor style
  //   additions ("Add X plugin") as new-plugin news and pass the rest
  //   through as marketplace activity.
  var m = String(rawTitle).match(/^Add (.+?) plugin(?: suite)?(?: \(#\d+\))?$/i)
  if (m && m[1]) item.title = "New plugin: " + m[1]
}

// ---- Filters and gathering -------------------------------------------------

function isCanary(item) {
  // Hermes publishes timestamped canary builds on the same release feed.
  // They already collide: many canary releases a week and only one line of
  // signal. Canary hidden per default.
  return /\+canary/i.test(item.title) || /\.canary/i.test(item.title)
}

function safeLink(item) {
  if (!item.link) return ""
  var m = item.link.match(/^https:\/\/([^/\/]+)(\/|$)/)
  if (!m) return ""
  if (ALLOWED_ORIGIN_HOSTS.indexOf(m[1]) < 0) return ""
  return item.link
}

function applySettings(items, settings) {
  var out = []
  var cutoff = Date.now() - MAX_ITEM_AGE_DAYS * 24 * 60 * 60 * 1000
  var keepCanary = !(settings && settings.filterCanary !== false)
  var maxItems = coerceInt(settings && settings.maxItems, 80, 20, 200)
  var enabled = {
    omarchy: !(settings && settings.sourceOmarchy === false),
    opencode: !(settings && settings.sourceOpencode === false),
    hermes: !(settings && settings.sourceHermes === false),
    marketplace: !(settings && settings.sourceMarketplace === false),
  }
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (!enabled[item.source]) continue
    if (item.source === "hermes" && isCanary(item) && !keepCanary) continue
    if (item.updatedMs && item.updatedMs < cutoff) continue
    out.push(item)
  }
  out.sort(byNewestFirst)
  if (out.length > maxItems) out.length = maxItems
  return out
}

function byNewestFirst(a, b) {
  if (b.updatedMs !== a.updatedMs) return b.updatedMs - a.updatedMs
  return String(a.id) < String(b.id) ? -1 : (String(a.id) === String(b.id) ? 0 : 1)
}

function coerceInt(value, fallback, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, Math.round(n)))
}

function dedupe(items) {
  var seen = {}
  var out = []
  for (var i = 0; i < items.length; i++) {
    var key = String(items[i].id)
    if (seen[key]) continue
    seen[key] = true
    out.push(items[i])
  }
  return out
}

function unreadCount(items, read) {
  var n = 0
  for (var i = 0; i < items.length; i++)
    if (read && read[String(items[i].id)]) continue
    else n++
  return n
}

// ---- Seen-state persistence -------------------------------------------------

var MAX_SEEN = 500

function normalizeSeen(raw) {
  // Whatever a torn file or hand edit contains, only bounded ids map to
  // bounded numbers, and the newest wins.
  var parsed
  try { parsed = JSON.parse(String(raw || "{}")) } catch (e) { parsed = null }
  if (!parsed || typeof parsed !== "object") parsed = {}
  // Tolerate a document wrapped one level too deep: view.read is meant to
  // be the flat id→timestamp map, and a wrapped copy must not become keys.
  var candidate = parsed.read
  if (candidate && candidate.read && typeof candidate.read === "object") candidate = candidate.read
  var read = candidate && typeof candidate === "object" ? candidate : {}
  var out = {}
  var n = 0
  for (var key in read) {
    if (!key || key.length > MAX_URL) continue
    var value = Number(read[key])
    if (!isFinite(value) || value < 0) continue
    out[key] = value
    n++
  }
  return { version: 1, read: trimSeen(out, MAX_SEEN) }
}

function trimSeen(read, limit) {
  var entries = []
  for (var key in read) {
    // Only flat id→timestamps survive; anything that leaked in wrapped
    // (values that are numbers) is dropped instead of growing nesting.
    var ts = Number(read[key])
    if (!isFinite(ts) || key === "version" || key === "read") continue
    entries.push([key, ts])
  }
  entries.sort(function (a, b) { return b[1] - a[1] })
  var out = {}
  for (var i = 0; i < Math.min(limit, entries.length); i++) out[entries[i][0]] = entries[i][1]
  return out
}

function mergeSeen(read, itemIds, timestampMs) {
  var next = read && typeof read === "object" ? Object.assign({}, read) : {}
  var ts = Number(timestampMs) || Date.now()
  for (var i = 0; i < itemIds.length; i++) {
    var key = String(itemIds[i] || "")
    if (!key) continue
    if (!next[key]) next[key] = ts
  }
  return trimSeen(next, MAX_SEEN)
}

function markAllSeen(read, items, timestampMs) {
  var ids = []
  for (var i = 0; i < items.length; i++) ids.push(String(items[i].id))
  return mergeSeen(read, ids, timestampMs)
}

// Bounded status summary for IPC status(): errors stay short and human.
function boundErrorText(text) {
  return String(text || "").replace(/\s+/g, " ").slice(0, 120)
}

function sourcesFromSettings(settings) {
  return [
    "omarchy",
    "opencode",
    "hermes",
    "marketplace",
  ].filter(function (id) {
    if (settings && settings["source" + id.charAt(0).toUpperCase() + id.slice(1)] === false) return false
    return true
  })
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    SOURCES: SOURCES,
    MAX_ITEMS_INPUT: MAX_ITEMS_INPUT,
    MAX_SEEN: MAX_SEEN,
    MAX_ITEM_AGE_DAYS: MAX_ITEM_AGE_DAYS,
    decodeEntities: decodeEntities,
    entryTag: entryTag,
    entryLink: entryLink,
    parseDateIso8601: parseDateIso8601,
    atomToItems: atomToItems,
    applyMarketplaceTitle: applyMarketplaceTitle,
    isCanary: isCanary,
    safeLink: safeLink,
    applySettings: applySettings,
    coerceInt: coerceInt,
    dedupe: dedupe,
    unreadCount: unreadCount,
    normalizeSeen: normalizeSeen,
    mergeSeen: mergeSeen,
    markAllSeen: markAllSeen,
    boundErrorText: boundErrorText,
    sourcesFromSettings: sourcesFromSettings,
  }
}
