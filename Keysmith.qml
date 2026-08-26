import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property color scrim: Color.menu.scrim
  property string fontFamily: Style.font.menuFamily

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/sinkeat.keysmith"
  readonly property string bindingsFile: Quickshell.env("HOME") + "/.config/hypr/bindings.lua"
  readonly property string omarchyBin: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/bin"

  property var rows: []
  property string filterText: ""
  property var selected: null
  property string viewState: "browsing"
  property bool capturePending: false
  property string capturedKey: ""
  property string status: ""
  property string loadError: ""
  property int actionMenuIndex: 0
  property string pendingReturnState: "browsing"
  property string pendingOperation: ""
  property string pendingSummary: ""
  property string successText: ""
  readonly property bool loading: root.viewState === "loading"
  readonly property bool capturing: root.viewState === "capturing"
  readonly property bool actionMenuOpen: root.viewState === "action-menu"
  readonly property bool removeConfirm: root.viewState === "remove-confirm"
  readonly property bool operationPending: root.viewState === "saving"
  readonly property bool blockedSelection: root.viewState === "blocked"
  readonly property var highlightedRow: {
    var i = list.currentIndex
    return i >= 0 && i < root.filtered.length ? root.filtered[i] : null
  }
  readonly property var actionMenuItems: {
    var items = []
    var row = root.selected
    if (!row)
      return items
    if (row.rebindable && !row.editor)
      items.push({ id: "change", label: row.key ? "Change shortcut" : "Add shortcut" })
    if (row.rebindable && row.key)
      items.push({ id: "remove", label: "Remove shortcut" })
    items.push({ id: "editor", label: "Open bindings.lua" })
    return items
  }

  Process {
    id: keysProc
    stdout: StdioCollector {
      id: keysOutput
    }
    onExited: function (exitCode) {
      if (!root.capturePending)
        return
      root.capturePending = false
      var key = keysOutput.text.trim()
      if (exitCode === 0 && key.length > 0) {
        root.capturedKey = key
        root.viewState = "captured"
        root.status = ""
        captureTimer.stop()
        return
      }
      // Stay in capture mode so an unsupported key never looks like a cancel.
      root.capturedKey = ""
      root.status = "unsupported key — press another combo or Escape to cancel"
    }
  }

  // Canonical form comes from keysmith-keys, never from QML, so the overlay
  // and the writer can never disagree about what key was pressed.
  function canonicalize(qtKey, qtMods) {
    root.capturedKey = ""
    root.status = ""
    root.capturePending = true
    keysProc.command = [root.pluginDir + "/keysmith-keys", "qt", String(qtKey), String(qtMods)]
    keysProc.running = true
  }

  function beginCaptureRow(row) {
    if (!row)
      return
    root.selected = row
    root.capturedKey = ""
    root.status = ""

    if (row.editor) {
      editorProc.running = true
      root.dismiss()
      return
    }

    // Design calls these rows visible for conflicts but not rebindable. Say so
    // instead of capturing a key we would only fail to write.
    if (!row.rebindable) {
      root.status = "view only — this shortcut is generated or shared, so Keysmith can't change it safely. It still counts as a conflict · Escape to go back"
      root.viewState = "blocked"
      return
    }

    root.viewState = "capturing"
    captureTimer.restart()
  }

  function beginCapture() {
    root.beginCaptureRow(root.highlightedRow)
  }

  function openActionMenu() {
    if (!root.highlightedRow)
      return
    root.selected = root.highlightedRow
    root.actionMenuIndex = 0
    root.status = ""
    root.viewState = "action-menu"
  }

  function closeActionMenu() {
    root.actionMenuIndex = 0
    root.selected = null
    root.status = ""
    root.viewState = "browsing"
  }

  function runActionMenu(index) {
    if (index < 0 || index >= root.actionMenuItems.length)
      return
    var actionId = root.actionMenuItems[index].id
    if (actionId === "change") {
      root.beginCaptureRow(root.selected)
      return
    }
    if (actionId === "remove") {
      root.status = ""
      root.viewState = "remove-confirm"
      return
    }
    editorProc.running = true
    root.dismiss()
  }

  function retryCapture() {
    root.capturedKey = ""
    root.status = ""
    root.viewState = "capturing"
    captureTimer.restart()
  }

  function cancelCapture() {
    root.capturePending = false
    if (keysProc.running)
      keysProc.running = false
    captureTimer.stop()
    root.capturedKey = ""
    root.selected = null
    root.status = ""
    root.viewState = "browsing"
  }

  function handleEscape() {
    // This is the single Escape path and it runs before every state-specific
    // key handler. Even a pending writer may be hidden safely while it finishes.
    if (root.operationPending || root.loading || root.viewState === "load-error") {
      root.dismiss()
      return
    }
    if (root.viewState === "success") {
      successTimer.stop()
      root.successText = ""
      root.dismiss()
      return
    }
    if (root.removeConfirm) {
      root.status = ""
      root.viewState = "action-menu"
      return
    }
    if (root.actionMenuOpen) {
      root.closeActionMenu()
      return
    }
    if (root.capturing || root.viewState === "captured" || root.blockedSelection) {
      root.cancelCapture()
      return
    }
    if (root.filterText)
      root.filterText = ""
    else
      root.dismiss()
  }

  Timer {
    id: captureTimer
    interval: 20000
    repeat: false
    onTriggered: {
      root.cancelCapture()
      root.dismiss()
    }
  }

  Process {
    id: writeProc
    onExited: function (exitCode) {
      if (exitCode === 0) {
        root.capturePending = false
        root.capturedKey = ""
        root.status = ""
        root.successText = root.pendingSummary
        root.pendingSummary = ""
        root.viewState = "success"
        successTimer.restart()
        return
      }
      root.pendingSummary = ""
      root.successText = ""
      root.viewState = root.pendingReturnState
      root.status = exitCode === 2 ? "already taken - nothing written"
        : exitCode === 3 ? "config error - change rolled back"
        : exitCode === 4 ? "rollback failed - check bindings.lua"
        : exitCode === 5 ? "can't read Hyprland state - nothing written"
        : exitCode === 6 ? "couldn't verify change - config restored"
        : "write failed (" + exitCode + ")"
    }
  }

  function commit() {
    if (!root.selected || !root.capturedKey || root.operationPending)
      return

    // Capturing the key it already has is a no-op, not a conflict with itself.
    if (root.selected.key && root.selected.key === root.capturedKey) {
      root.cancelCapture()
      root.dismiss()
      return
    }

    root.pendingOperation = root.selected.key ? "change" : "add"
    root.pendingReturnState = "captured"
    root.pendingSummary = root.selected.key
      ? "Changed “" + root.selected.label + "” from " + root.selected.key + " to " + root.capturedKey
      : "Added " + root.capturedKey + " to “" + root.selected.label + "”"
    root.status = "saving..."
    root.viewState = "saving"
    // The old key rides along: without it the writer can only add a second
    // shortcut, never move the existing one.
    var cmd = [root.pluginDir + "/keysmith-write", root.capturedKey,
               root.selected.key || "", root.selected.identityLabel || root.selected.label,
               root.selected.action || ""]
    var conflict = root.conflictFor(root.capturedKey)
    if (conflict && conflict.key !== root.selected.key)
      cmd.push("--replace")
    writeProc.command = cmd
    writeProc.running = true
  }

  function confirmRemove() {
    if (!root.selected || !root.selected.key || !root.selected.action || root.operationPending)
      return
    root.pendingOperation = "remove"
    root.pendingReturnState = "remove-confirm"
    root.pendingSummary = "Removed " + root.selected.key + " from “" + root.selected.label + "”"
    root.status = "removing..."
    root.viewState = "saving"
    writeProc.command = [root.pluginDir + "/keysmith-write", "remove",
                         root.selected.key,
                         root.selected.identityLabel || root.selected.label,
                         root.selected.action]
    writeProc.running = true
  }

  Timer {
    id: successTimer
    interval: 1100
    repeat: false
    onTriggered: {
      root.successText = ""
      root.selected = null
      root.viewState = "browsing"
      root.dismiss()
    }
  }

  Process {
    id: readProc
    command: [root.pluginDir + "/keysmith-read"]
    stdout: StdioCollector {
      id: readOutput
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.rows = []
        root.loadError = "can't read Hyprland bindings — close and try again"
        root.viewState = "load-error"
        return
      }
      try {
        root.rows = JSON.parse(readOutput.text)
        root.viewState = "browsing"
      } catch (e) {
        root.rows = []
        root.loadError = "binding catalog returned invalid data"
        root.viewState = "load-error"
      }
    }
  }

  function conflictFor(canonicalKey) {
    var conflicts = root.conflictsFor(canonicalKey)
    return conflicts.length > 0 ? conflicts[0] : null
  }

  function conflictsFor(canonicalKey) {
    var conflicts = []
    if (!canonicalKey)
      return conflicts
    for (var i = 0; i < root.rows.length; i++)
      if (root.rows[i].key === canonicalKey)
        conflicts.push(root.rows[i])
    return conflicts
  }

  // The last row is an escape hatch, not a binding: the rows we refuse to
  // rebind tell the user to edit the file, so let them open it from here.
  readonly property var editorRow: ({
    label: "Open bindings.lua in editor",
    key: null, source: "editor", action: "", rebindable: true, editor: true
  })

  readonly property var filtered: {
    if (root.loading)
      return []
    var q = root.filterText.toLowerCase()
    var out = q ? root.rows.filter(function (r) {
      return r.label.toLowerCase().indexOf(q) !== -1
    }) : root.rows
    return out.slice(0, 200).concat([root.editorRow])
  }

  Process {
    id: editorProc
    command: [root.omarchyBin + "/omarchy-launch-editor", root.bindingsFile]
  }

  function open(payloadJson) {
    if (writeProc.running) {
      root.viewState = "saving"
      root.opened = true
      Qt.callLater(function () { keyCatcher.forceActiveFocus() })
      return
    }

    successTimer.stop()
    captureTimer.stop()
    root.filterText = ""
    root.selected = null
    root.capturePending = false
    root.capturedKey = ""
    root.status = ""
    root.loadError = ""
    root.actionMenuIndex = 0
    root.pendingReturnState = "browsing"
    root.pendingOperation = ""
    root.pendingSummary = ""
    root.successText = ""
    root.rows = []
    root.viewState = "loading"
    readProc.running = true
    root.opened = true
    Qt.callLater(function () {
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    captureTimer.stop()
    root.capturePending = false
    if (keysProc.running)
      keysProc.running = false
    root.opened = false
  }

  function dismiss() {
    captureTimer.stop()
    root.capturePending = false
    if (keysProc.running)
      keysProc.running = false
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "sinkeat.keysmith")
  }

  function toggle() {
    if (root.opened)
      root.dismiss()
    else
      root.open("{}")
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "keysmith"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Suppresses Hyprland's own keybinds while recording, so pressing a combo
    // that is already taken reaches us instead of firing what owns it.
    ShortcutInhibitor {
      id: inhibitor
      window: panel
      enabled: root.capturing
    }

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Rectangle {
      id: card
      width: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(420), panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: root.background
      border.color: root.borderColor
      border.width: 1

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Column {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.space(8)

        Text {
          width: parent.width
          elide: Text.ElideRight
          text: root.filterText.length ? root.filterText : "Type to search…"
          opacity: root.filterText.length ? 1.0 : 0.5
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.borderColor
          opacity: 0.5
        }

        Text {
          visible: root.viewState === "load-error"
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.loadError
          color: root.foreground
          opacity: 0.75
          font.family: root.fontFamily
        }

        Column {
          visible: root.loading
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            text: "Loading shortcuts…"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Reading your Omarchy shortcuts and installed apps."
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
          }
        }

        Column {
          visible: root.operationPending
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            text: root.pendingOperation === "remove"
              ? "Removing shortcut…" : "Saving shortcut…"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Escape or click outside to hide Keysmith. The verified write will continue safely."
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
          }
        }

        Column {
          visible: root.viewState === "success"
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.successText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Text {
            text: "Done"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
          }
        }

        Column {
          visible: root.actionMenuOpen
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.selected ? root.selected.label : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Repeater {
            model: root.actionMenuItems
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: parent.width
              height: Style.space(30)
              color: index === root.actionMenuIndex
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: root.foreground
                font.family: root.fontFamily
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.actionMenuIndex = index
                  root.runActionMenu(index)
                }
              }
            }
          }

          Text {
            text: "Up/Down to choose · Enter to open · Left or Escape to go back"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
          }
        }

        Column {
          visible: root.removeConfirm
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.selected
              ? "Remove " + root.selected.key + " from “" + root.selected.label + "”?"
              : "Remove shortcut?"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "The item will have no shortcut. This does not restore an Omarchy default."
            color: root.foreground
            opacity: 0.65
            font.family: root.fontFamily
          }

          Row {
            spacing: Style.space(8)

            KeysmithButton {
              width: Style.space(150)
              label: "Remove · Enter"
              primary: true
              onTriggered: root.confirmRemove()
            }

            KeysmithButton {
              width: Style.space(130)
              label: "Cancel · Escape"
              onTriggered: {
                root.status = ""
                root.viewState = "action-menu"
              }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: root.status.length > 0
            text: root.status
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
          }
        }

        Column {
          visible: root.capturing || root.viewState === "captured" || root.blockedSelection
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.selected ? root.selected.label : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Text {
            visible: !root.blockedSelection
            width: parent.width
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            text: root.capturedKey.length ? root.capturedKey : "Press the keys you want…"
            opacity: root.capturedKey.length ? 1.0 : 0.6
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: root.capturedKey.length > 0
            color: root.foreground
            font.family: root.fontFamily
            text: {
              if (root.selected && root.selected.key === root.capturedKey)
                return "unchanged — this is already the shortcut"
              var conflicts = root.conflictsFor(root.capturedKey)
              if (conflicts.length === 0)
                return "free — nothing else uses this"
              if (conflicts.length === 1)
                return "taken by \"" + conflicts[0].label + "\""
              return "taken by " + conflicts.length + " shortcuts: "
                + conflicts.map(function (row) { return row.label }).join(", ")
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: root.status.length > 0
            text: root.status
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
          }

          Row {
            visible: !root.blockedSelection
            spacing: Style.space(8)

            KeysmithButton {
              visible: root.capturedKey.length > 0
              width: Style.space(140)
              label: {
                var conflicts = root.conflictsFor(root.capturedKey)
                if (conflicts.length === 0)
                  return "Save · Enter"
                return conflicts.length === 1
                  ? "Replace · Enter"
                  : "Replace " + conflicts.length + " · Enter"
              }
              primary: true
              onTriggered: root.commit()
            }

            KeysmithButton {
              visible: root.capturedKey.length > 0
              width: Style.space(195)
              label: "Try another · Backspace"
              onTriggered: root.retryCapture()
            }

            KeysmithButton {
              width: Style.space(120)
              label: "Cancel · Esc"
              onTriggered: root.cancelCapture()
            }
          }
        }

        ListView {
          id: list
          visible: root.viewState === "browsing"
          width: parent.width
          height: parent.height - Style.space(104)
          clip: true
          model: root.filtered
          currentIndex: 0
          keyNavigationEnabled: false

          delegate: Rectangle {
            width: ListView.view.width
            height: Style.space(26)
            color: ListView.isCurrentItem
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
              : "transparent"

            Text {
              id: rowLabel
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.right: shortcutText.visible ? shortcutText.left
                : (rowState.visible ? rowState.left : parent.right)
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: modelData.label
              color: root.foreground
              opacity: modelData.rebindable ? 1.0 : 0.45
              font.family: root.fontFamily
            }

            Text {
              id: shortcutText
              visible: text.length > 0
              anchors.right: rowState.visible ? rowState.left : parent.right
              anchors.rightMargin: rowState.visible ? Style.space(8) : Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.key || ""
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
            }

            Text {
              id: rowState
              visible: text.length > 0
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.key && !modelData.rebindable ? "· view only"
                : (!modelData.key && (modelData.source === "app" || modelData.source === "action")
                   ? "not bound" : "")
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                list.currentIndex = index
                keyCatcher.forceActiveFocus()
              }
              onDoubleClicked: {
                list.currentIndex = index
                root.beginCaptureRow(modelData)
              }
            }
          }
        }

        Row {
          visible: list.visible && root.highlightedRow
          spacing: Style.space(8)

          KeysmithButton {
            width: Style.space(220)
            label: {
              var row = root.highlightedRow
              if (!row)
                return ""
              if (row.editor)
                return "Open editor · Enter"
              if (!row.rebindable)
                return "Why view only? · Enter"
              return (row.key ? "Change shortcut" : "Add shortcut") + " · Enter"
            }
            primary: true
            onTriggered: root.beginCapture()
          }

          KeysmithButton {
            width: Style.space(175)
            label: "More… · Right Arrow"
            onTriggered: root.openActionMenu()
          }
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          // Escape is always handled first. The panel owns exclusive keyboard
          // focus, so no interaction state may intercept or defer this path.
          if (event.key === Qt.Key_Escape) {
            root.handleEscape()
            event.accepted = true
            return
          }

          if (root.operationPending || root.loading || root.viewState === "load-error") {
            event.accepted = true
            return
          }

          if (root.viewState === "success") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              successTimer.stop()
              root.successText = ""
              root.dismiss()
            }
            event.accepted = true
            return
          }

          if (root.removeConfirm) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
              root.confirmRemove()
            event.accepted = true
            return
          }

          if (root.actionMenuOpen) {
            if (event.key === Qt.Key_Left) {
              root.closeActionMenu()
            } else if (event.key === Qt.Key_Down) {
              if (root.actionMenuIndex < root.actionMenuItems.length - 1)
                root.actionMenuIndex++
            } else if (event.key === Qt.Key_Up) {
              if (root.actionMenuIndex > 0)
                root.actionMenuIndex--
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.runActionMenu(root.actionMenuIndex)
            }
            event.accepted = true
            return
          }

          if (root.capturing) {
            if (root.capturePending) {
              event.accepted = true
              return
            }
            // Bare modifier presses are not a shortcut yet.
            if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control
                || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta
                || event.key === Qt.Key_AltGr || event.key === Qt.Key_CapsLock) {
              event.accepted = true
              return
            }
            root.canonicalize(event.key, event.modifiers)
            event.accepted = true
            return
          }

          if (root.viewState === "captured") {
            if (event.key === Qt.Key_Backspace) {
              root.retryCapture()
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.commit()
            }
            event.accepted = true
            return
          }

          if (root.blockedSelection) {
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.beginCapture()
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.openActionMenu()
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            if (list.currentIndex < root.filtered.length - 1)
              list.currentIndex++
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            if (list.currentIndex > 0)
              list.currentIndex--
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            root.filterText = root.filterText.slice(0, -1)
            list.currentIndex = 0
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32
                     && event.text.charCodeAt(0) !== 127) {
            root.filterText += event.text
            list.currentIndex = 0
            event.accepted = true
          }
        }
      }
    }
  }
}
