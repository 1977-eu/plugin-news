import QtQuick
import Quickshell
import Quickshell.Io
import "NewsModel.js" as NewsModel

// Headless poller for 1977.news. One instance per enabled plugin; bar
// widgets on every monitor resolve this singleton instead of polling.
//
// The service owns:
//   - the four bounded fetches (GitHub atom feeds, unauthenticated, GET only)
//   - the newest-first item list and its canary/source filters
//   - seen state, persisted to XDG state so marked items survive restarts
// Visual instances own selection, scroll and which story is open.
//
// A refresh guards against overlap, so each cycle has a single generation:
// whichever source answers late still belongs to the one running cycle, and
// a fresh application of settings during a cycle is deferred to the next one.

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // Written on startup and by the widget through applySettings(); plain
  // clamped copies of what lives on the bar-widget entry in shell.json.
  property var settings: ({
    pollMinutes: 20,
    filterCanary: true,
    maxItems: 80,
    sourceOmarchy: false,
    sourceOpencode: true,
    sourceHermes: true,
    sourceMarketplace: false,
    sourceSite: true,
  })

  // Newest first, capped by settings.maxItems.
  readonly property var items: view.items
  readonly property int unreadCount: view.unreadCount
  // Keyed by item id, values are mark timestamps; the list panel reads it
  // through here because the internal view item is private on purpose.
  readonly property var readModel: view.read
  readonly property bool refreshing: activeFetches > 0
  // A cycle where every enabled source failed means the badge reads
  // "this is yesterday's news", not "the world ran out of releases".
  readonly property bool stale: polledOnce && !refreshing && lastCycleHadSuccess === false
  readonly property string lastError: view.lastError

  property int activeFetches: 0
  property bool polledOnce: false
  property bool cycleHadSuccess: false
  property bool lastCycleHadSuccess: false
  property double lastSuccessMs: 0
  readonly property int pollMs: NewsModel.coerceInt(settings.pollMinutes, 20, 5, 240) * 60 * 1000

  function refresh() {
    // No overlapping cycles: a poll landing mid-cycle becomes the next one.
    if (root.activeFetches > 0) return
    var enabled = NewsModel.sourcesFromSettings(root.settings)
    // Only sources with a live fetcher may be counted, or a settings/source
    // mismatch would pin activeFetches above zero and freeze the badge.
    root.activeFetches = 0
    root.cycleHadSuccess = false
    for (var i = 0; i < enabled.length; i++) {
      var proc = root.fetchers[enabled[i]]
      if (proc) {
        root.activeFetches++
      } else {
        view.setSourceStatus(enabled[i], "err")
      }
    }
    if (root.activeFetches === 0) return
    for (i = 0; i < enabled.length; i++) {
      proc = root.fetchers[enabled[i]]
      if (proc) {
        view.setSourceStatus(enabled[i], "loading")
        proc.running = true
      }
    }
  }

  function sourceCollected(sourceId, body) {
    var ok = view.collect(String(sourceId), String(body))
    if (ok) root.cycleHadSuccess = true
  }

  function sourceExited(sourceId, exitCode) {
    if (exitCode !== 0) view.bindError(String(sourceId),
      "curl " + Number(exitCode) + " on " + sourceId)
    root.activeFetches = Math.max(0, root.activeFetches - 1)
    if (root.activeFetches > 0) return
    root.lastCycleHadSuccess = root.cycleHadSuccess
    root.polledOnce = true
    if (root.lastCycleHadSuccess) {
      view.lastError = ""
      root.lastSuccessMs = Date.now()
    } else {
      // Nothing arrived this cycle: keep prior items, flag the badge.
      view.lastError = view.boundLastError()
    }
  }

  function applySettings(next) {
    // Callers hand this a JSON string (IPC arg or widget payload); accept a
    // plain object too. A string would make every `x !== false` guard read
    // undefined !== false and silently flip toggles on.
    var obj = next
    if (typeof obj === "string") {
      try { obj = JSON.parse(obj) } catch (e) { obj = null }
    }
    var clean = {
      pollMinutes: NewsModel.coerceInt(obj && obj.pollMinutes, 20, 5, 240),
      filterCanary: obj ? obj.filterCanary !== false : true,
      maxItems: NewsModel.coerceInt(obj && obj.maxItems, 80, 20, 200),
      sourceOmarchy: obj ? obj.sourceOmarchy !== false : false,
      sourceOpencode: obj ? obj.sourceOpencode !== false : true,
      sourceHermes: obj ? obj.sourceHermes !== false : true,
      sourceMarketplace: obj ? obj.sourceMarketplace !== false : false,
      sourceSite: obj ? obj.sourceSite !== false : true,
    }
    var sourcesChanged = NewsModel.sourcesFromSettings(clean).join(",")
      !== NewsModel.sourcesFromSettings(root.settings).join(",")
    root.settings = clean
    view.reapply()
    pollTimer.interval = root.pollMs
    if (sourcesChanged && !root.refreshing) root.refresh()
  }

  function markRead(ids) {
    if (!ids || ids.length === 0) return
    view.read = NewsModel.mergeSeen(view.read, ids)
    view.delayedWriteSeen()
  }

  function markAllRead() {
    view.read = NewsModel.markAllSeen(view.read, view.items)
    view.delayedWriteSeen()
  }

  // ---- fetching -----------------------------------------------------------

  // One curl per source: argument arrays only, hard time and size bounds,
  // no shell. GitHub atom feeds run well under 100 KB; 256 KiB covers any
  // burst the feed ever produces and refuses bigger bodies outright.
  component SourceFetch: Process {
    property string sourceId: ""

    // Overridden per instance with the fixed feed URL as the last argument.
    command: [
      "curl", "--silent", "--show-error", "--location",
      "--max-time", "15", "--max-redirs", "3", "--max-filesize", "262144",
      "-H", "Accept: application/atom+xml",
      "--url", ""
    ]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sourceCollected(sourceId, String(text || ""))
    }
    onExited: function(exitCode) { root.sourceExited(sourceId, exitCode) }
  }

  SourceFetch {
    id: fetchOmarchy
    sourceId: "omarchy"
    Component.onCompleted: {
      command[command.length - 1] = "https://github.com/omacom/omarchy/releases.atom"
    }
  }
  SourceFetch {
    id: fetchOpencode
    sourceId: "opencode"
    Component.onCompleted: {
      command[command.length - 1] = "https://github.com/anomalyco/opencode/releases.atom"
    }
  }
  SourceFetch {
    id: fetchHermes
    sourceId: "hermes"
    Component.onCompleted: {
      command[command.length - 1] = "https://github.com/NousResearch/Hermes-Agent/releases.atom"
    }
  }
  SourceFetch {
    id: fetchMarketplace
    sourceId: "marketplace"
    Component.onCompleted: {
      command[command.length - 1] = "https://github.com/omacom/omarchy-plugin-marketplace/commits/main/registry.json.atom"
    }
  }
  SourceFetch {
    id: fetchSite
    sourceId: "site"
    Component.onCompleted: {
      command[command.length - 1] = "https://omarchy.org/news/rss.xml"
    }
  }

  readonly property var fetchers: ({
    omarchy: fetchOmarchy,
    opencode: fetchOpencode,
    hermes: fetchHermes,
    marketplace: fetchMarketplace,
    site: fetchSite,
  })

  // ---- seen-state persistence (XDG state, external owner) -----------------

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || ((Quickshell.env("HOME") || "~") + "/.local/state")) + "/1977-news"

  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: loadSeen(text())
    // First run: the file does not exist yet; seen state stays empty.
    onLoadFailed: loadSeen("")
  }

  Process {
    id: ensureDirsProc
    command: ["mkdir", "-p", root.stateDir]
  }

  function loadSeen(raw) {
    var parsed = NewsModel.normalizeSeen(raw)
    view.read = parsed.read
    view.reapply()
  }

  function writeSeen() {
    stateFile.setText(JSON.stringify({ version: 1, read: view.read }, null, 2) + "\n")
  }

  // ---- view model ---------------------------------------------------------

  Item {
    id: view

    readonly property var items: mergedItems
    readonly property int unreadCount: NewsModel.unreadCount(mergedItems, read)
    property var read: ({})
    property var mergedItems: []
    property string lastError: ""
    // per source: idle | loading | ok | bad | err
    property var sourceStatus: ({
      omarchy: "idle", opencode: "idle", hermes: "idle", marketplace: "idle", site: "idle",
    })
    property var rawBySource: ({})

    function collect(sourceId, raw) {
      // Atom stores items in <entry>, RSS 2.0 in <item>; both are ours now.
      var hasEntries = raw.indexOf("<entry>") >= 0 || raw.indexOf("<item>") >= 0
      if (hasEntries) rawBySource[sourceId] = raw.slice(0, 262144)
      setSourceStatus(sourceId, hasEntries ? "ok" : "err")
      reapply()
      return hasEntries
    }

    function setSourceStatus(sourceId, status) {
      var next = Object.assign({}, sourceStatus)
      next[sourceId] = status || "idle"
      sourceStatus = next
    }

    function bindError(sourceId, message) {
      setSourceStatus(sourceId, "err")
      lastError = NewsModel.boundErrorText(message)
    }

    function boundLastError() {
      var failed = []
      for (var key in sourceStatus)
        if (sourceStatus[key] === "err" || sourceStatus[key] === "bad") failed.push(key)
      return failed.length > 0
        ? NewsModel.boundErrorText("Failed: " + failed.join(", ")) : lastError
    }

    function reapply() {
      // Filter, dedupe and cap whatever is currently collected; a source
      // clears its raw payload again when its toggle turns off in settings.
      var all = []
      var enabled = {}
      var list = NewsModel.sourcesFromSettings(root.settings)
      for (var i = 0; i < list.length; i++) enabled[list[i]] = true
      for (var key in rawBySource) {
        if (!enabled[key]) continue
        var parsed = NewsModel.parseFeed(rawBySource[key], key)
        for (var j = 0; j < parsed.length; j++) all.push(parsed[j])
      }
      mergedItems = NewsModel.applySettings(NewsModel.dedupe(all), root.settings)
      lastError = boundLastError()
    }

    function delayedWriteSeen() {
      seenSaveTimer.restart()
    }
  }

  Timer {
    id: seenSaveTimer
    interval: 400
    onTriggered: root.writeSeen()
  }

  Timer {
    id: pollTimer
    interval: root.pollMs
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    ensureDirsProc.running = true
    Qt.callLater(function() { stateFile.reload() })
  }

  IpcHandler {
    target: "1977.news"
    function refresh(): void { root.refresh() }
    function markAllRead(): void { root.markAllRead() }
    // Bounded status: scalars only, no payloads and no raw feed text.
    function status(): string {
      return JSON.stringify({
        refreshing: root.refreshing,
        stale: root.stale,
        error: root.lastError !== "",
        items: view.items.length,
        unread: root.unreadCount,
      })
    }
    function applySettings(settingsJson: string): string {
      try { root.applySettings(JSON.parse(String(settingsJson || "{}"))); return "ok" }
      catch (e) { return "bad" }
    }
  }
}
