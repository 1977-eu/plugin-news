import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "NewsModel.js" as NewsModel

// News badge for 1977.news: unread count of Omarchy / OpenCode / Hermes
// releases plus new marketplace plugins. Left click toggles the news list
// popout, right click forces a refresh. Polling and seen-state live in the
// plugin service; everything visual here is per instance.

BarWidget {
  id: root
  moduleName: "1977.news"

  // Own-service lookup. Under the trusted built-in bar the widget's `bar` is
  // a PluginBarApi facade whose `shell` is the service-capable plugin facade;
  // on a replacement bar that facade arrives without a shell, so the badge
  // degrades to a plain launcher there.
  readonly property var shellFacade: root.bar && root.bar.shell ? root.bar.shell
    : (root.shell || null)
  readonly property var svc: shellFacade && typeof shellFacade.serviceFor === "function"
    ? shellFacade.serviceFor("1977.news") || null : null
  readonly property int unreadCount: svc ? svc.unreadCount : 0
  readonly property bool svcRefreshing: svc ? svc.refreshing : false
  readonly property bool svcStale: svc ? svc.stale : false
  readonly property string svcError: svc ? svc.lastError : ""

  // Settings go straight to the service; the poller owns behavior, the
  // widget is one of possibly several views. re-apply on reload too.
  function syncSettings() {
    if (!svc || typeof svc.applySettings !== "function") return
    var payload = {
      pollMinutes: setting("pollMinutes", 20),
      filterCanary: setting("filterCanary", true) !== false,
      maxItems: setting("maxItems", 80),
      sourceOmarchy: setting("sourceOmarchy", false) !== false,
      sourceOpencode: setting("sourceOpencode", true) !== false,
      sourceHermes: setting("sourceHermes", true) !== false,
      sourceMarketplace: setting("sourceMarketplace", false) !== false,
      sourceSite: setting("sourceSite", true) !== false,
    }
    svc.applySettings(JSON.stringify(payload))
  }

  onSvcChanged: syncSettings()
  onBarChanged: { injectPanel(); syncSettings() }
  onSettingsChanged: { syncSettings(); injectPanel() }

  function refreshNow() {
    if (svc && typeof svc.refresh === "function") svc.refresh()
  }

  // ---- news list popout. Shape contract for shell.summon/toggle routing:
  // open/close/opened live on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("shell" in target) target.shell = root.shellFacade
  }

  // Marked read in one place: opening the list everybody already sees in
  // the badge leaves it at zero. Items arriving unopened stay unread.
  function markAll() {
    if (svc && typeof svc.markAllRead === "function") svc.markAllRead()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical
      ? (root.unreadCount > 0 ? "N" : "n")
      : (root.unreadCount > 0 ? "News " + root.unreadCount : "News")
    labelVisible: !root.vertical
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75
    // Every sink is external text: plain text only.
    tooltipText: root.svcError
      ? (NewsModel.boundErrorText(root.svcError) + " — left-click list, right-click refresh")
      : (root.svcStale
        ? "Feeds unreachable, showing last known news — left-click list, right-click refresh"
        : "Ecosystem news: Omarchy, OpenCode, Hermes, marketplace — left-click list, right-click refresh")

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refreshNow()
      else root.togglePanel()
    }

    // Refresh pulse: while fetches are in flight the dot reads as activity so
    // a long offline stretch does not look like a hung widget.
    Rectangle {
      visible: root.svcRefreshing && root.unreadCount === 0
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(5)
      height: width
      radius: width / 2
      color: button.foreground
      opacity: 0.7
    }
  }
}
