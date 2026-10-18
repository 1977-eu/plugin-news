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

  // Own-service lookup. Third-party widgets may only ever reach their own
  // service through the injected facade; on a replacement bar that facade
  // omits the service, so the badge degrades to a plain launcher there.
  readonly property var svc: root.shell && typeof root.shell.serviceFor === "function"
    ? root.shell.serviceFor("1977.news") || null : null
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
      sourceOmarchy: setting("sourceOmarchy", true) !== false,
      sourceOpencode: setting("sourceOpencode", true) !== false,
      sourceHermes: setting("sourceHermes", true) !== false,
      sourceMarketplace: setting("sourceMarketplace", true) !== false,
    }
    svc.applySettings(JSON.stringify(payload))
  }

  onSvcChanged: syncSettings()
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
  }

  // Marked read in one place: opening the list everybody already sees in
  // the badge leaves it at zero. Items arriving unopened stay unread.
  function markAll() {
    if (svc && typeof svc.markAllRead === "function") svc.markAllRead()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

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
    text: root.vertical ? (root.unreadCount > 0 ? "N" : "n")
      : "News"
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

    // Unread badge: a small count beside the label, absent when everything
    // is read so a settled inbox does not paint a permanent chip.
    Rectangle {
      id: badge
      visible: root.unreadCount > 0
      radius: height / 2
      height: Math.max(Style.space(14), Math.round(Style.bar.iconSlot * 0.5))
      width: badgeText.implicitWidth + Style.space(8)
      color: (bar ? bar.urgent : Commons.Color.accent)
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.right
      anchors.leftMargin: -Style.space(16)

      Text {
        id: badgeText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: String(root.unreadCount)
        color: Commons.Color.background
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // Refresh pulse: while fetches are in flight the badge reads as a dot so
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
