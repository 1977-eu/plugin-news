import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "NewsModel.js" as NewsModel

// The news list popout for 1977.news. The badge lives on the widget; this
// panel owns reading: the list, keyboard cursor, open-in-browser and
// mark-read. Everything displayed comes from the feeds and is bounded by
// NewsModel at parse time, so every sink stays plain text.

Panel {
  id: root
  moduleName: "1977.news"
  ipcTarget: "1977.news"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  // The widget hands its service-capable PluginBarApi shell down; on the
  // built-in bar that carries serviceFor() for own-plugin lookups only.
  property var shell: null
  readonly property var barIdentity: hostWidget || root

  // Resolution order: whatever the badge already resolved (hostWidget.svc),
  // else the injected shell facade. A service-less replacement bar leaves
  // the list empty with a friendly note rather than a hostile blank surface.
  readonly property var shellFacade: shell && typeof shell.serviceFor === "function" ? shell : null
  readonly property var svc: (hostWidget && hostWidget.svc) ? hostWidget.svc
    : (shellFacade ? shellFacade.serviceFor("1977.news") || null : null)
  readonly property var items: svc ? svc.items : []
  readonly property bool refreshing: svc ? svc.refreshing : false
  readonly property bool stale: svc ? svc.stale : false
  readonly property string errorText: svc ? svc.lastError : ""

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.accent

  property int cursorIndex: 0
  readonly property bool deadList: !items || items.length === 0
  readonly property var cursorItem: deadList ? null : items[cursorIndex]
  // Display rows: one header per project group followed by its items. The
  // cursor keeps addressing item indices, so headers are display-only.
  readonly property var rows: deadList ? [] : NewsModel.groupedRows(items)

  readonly property var sourceLabels: ({
    omarchy: "OM", opencode: "OC", hermes: "HE", marketplace: "MP", site: "NW",
  })

  function refreshNow() {
    if (svc && typeof svc.refresh === "function") svc.refresh()
  }

  function markAll() {
    if (svc && typeof svc.markAllRead === "function") svc.markAllRead()
  }

  function markRead(item) {
    if (!item || !svc || typeof svc.markRead !== "function") return
    svc.markRead([String(item.id)])
  }

  // Only our four source hosts' page URLs ever open; NewsModel.safeLink is
  // the allowlist, and it returns "" for anything else.
  function openStory(item) {
    if (!item) return
    markRead(item)
    var link = NewsModel.safeLink(item)
    if (link === "") return
    Quickshell.execDetached(["xdg-open", link])
  }

  function relativeAge(ms) {
    if (!ms) return ""
    var sec = Math.max(0, (Date.now() - ms) / 1000)
    if (sec < 60) return "now"
    if (sec < 3600) return Math.floor(sec / 60) + "m"
    if (sec < 86400) return Math.floor(sec / 3600) + "h"
    return Math.floor(sec / 86400) + "d"
  }

  function moveCursorStep(delta) {
    if (root.deadList) return
    root.cursorIndex = Math.max(0, Math.min(root.items.length - 1, root.cursorIndex + delta))
  }

  function resetCursor() {
    root.cursorIndex = 0
  }

  onOpenedChanged: if (opened) resetCursor()
  onItemsChanged: {
    if (root.cursorIndex >= root.items.length)
      root.cursorIndex = Math.max(0, root.items.length - 1)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(panel.listWidth)
    contentHeight: panel.fittedContentHeight(listColumn.implicitHeight, Style.space(520))
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursorStep(dy)
      }
      onActivateRequested: root.openStory(root.cursorItem)
      // x marks the story under the cursor read without opening it.
      onDeleteRequested: root.markRead(root.cursorItem)
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "m" || t === "M") root.markAll()
      }
    }

    readonly property real listWidth: Style.space(430)

    Column {
      id: listColumn
      // Fit the card's interior: contentHolder is already inset by the
      // border/padding, so sizing to parent.width keeps chips inside the
      // card instead of escaping through the right edge.
      width: parent.width
      spacing: Style.space(4)

      // ---- header: title, status, actions
      Item {
        width: parent.width
        height: Style.space(22)

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Ecosystem news"
          color: root.foreground
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.heading
        }

        Text {
          textFormat: Text.PlainText
          anchors.right: refreshButton.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: root.refreshing ? "checking..." : (root.stale ? "stale" : "")
          color: root.dim
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        PanelActionButton {
          id: refreshButton
          iconText: root.refreshing ? "…" : "↻"
          tooltipText: "Refresh now (R)"
          visible: true
          foreground: root.foreground
          hasCursor: true
          anchors.right: markAllButton.left
          anchors.rightMargin: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.refreshNow()
        }

        PanelActionButton {
          id: markAllButton
          iconText: "✓"
          tooltipText: "Mark all read (M)"
          foreground: root.foreground
          hasCursor: true
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.markAll()
        }
      }

      // ---- bounded error line (already capped at parse/merge time)
      Text {
        textFormat: Text.PlainText
        visible: root.errorText !== ""
        width: parent.width
        text: root.errorText
        color: root.urgent
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        visible: root.items.length === 0
        width: parent.width
        text: root.refreshing
          ? "Fetching feeds..."
          : (root.svc ? "No ecosystem news." : "News service not available on this bar.")
        color: root.dim
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      // ---- list
      Flickable {
        id: listScroll
        width: parent.width
        height: Math.min(rowsColumn.implicitHeight, Style.space(420))
        contentWidth: width
        contentHeight: rowsColumn.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: rowsColumn
          width: listScroll.width
          spacing: Style.space(2)

          Repeater {
            model: root.rows

            delegate: Item {
              id: row
              required property var modelData
              required property int index
              readonly property bool isHeader: modelData.kind === "header"
              readonly property int itemIndex: isHeader ? -1 : modelData.itemIndex
              readonly property var story: isHeader ? null : modelData.item
              readonly property bool isCurrent: !isHeader && root.cursorIndex === itemIndex
              readonly property bool isRead:
                !isHeader && !!(root.svc && root.svc.readModel
                  && root.svc.readModel[String(modelData.item.id)])

              width: parent ? parent.width : 0
              height: isHeader ? Style.space(22) : Style.space(32)

              // ---- group header row
              Text {
                id: groupLabel
                visible: row.isHeader
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                text: (String(modelData.label || "?").toUpperCase()
                       + " · " + modelData.count)
                color: root.dim
                font.family: bar ? bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Rectangle {
                visible: row.isHeader
                anchors.left: groupLabel.right
                anchors.leftMargin: Style.space(8)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(2)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(7)
                height: 1
                color: root.dim
                opacity: 0.35
              }

              // ---- story row (headers stop here)
              CursorSurface {
                visible: !row.isHeader
                anchors.fill: parent
                foreground: root.foreground
                current: row.isCurrent
              }

              Rectangle {
                // Unread dot.
                visible: !row.isHeader && !row.isRead
                anchors.left: parent.left
                anchors.leftMargin: Style.space(3)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(4)
                height: width
                radius: width / 2
                color: root.urgent
              }

              Text {
                textFormat: Text.PlainText
                visible: !row.isHeader
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.right: rowMeta.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: String(story ? story.title || "" : "")
                color: row.isRead ? root.dim : root.foreground
                font.family: bar ? bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Item {
                id: rowMeta
                visible: !row.isHeader
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                width: chipText.implicitWidth + ageText.implicitWidth + Style.space(16)
                height: row.height

                Text {
                  id: chipText
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.sourceLabels[String(story ? story.source : "")] || "?"
                  color: root.dim
                  font.family: bar ? bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: ageText
                  anchors.left: chipText.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.relativeAge(story ? story.updatedMs || 0 : 0)
                  color: root.dim
                  font.family: bar ? bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                visible: !row.isHeader
                anchors.fill: parent
                onClicked: function(mouse) { root.openStory(row.story) }
                onEntered: root.cursorIndex = row.itemIndex
              }
            }
          }
        }
      }

      // ---- footer hint
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "↑/↓ browse · ↵ open · x mark read · R refresh · Esc close"
        color: root.dim
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        opacity: 0.75
      }
    }
  }
}
