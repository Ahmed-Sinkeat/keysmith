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

  property var rows: []
  property string filterText: ""
  property var selected: null

  property bool capturing: false
  property string capturedKey: ""
  property string status: ""

  Process {
    id: keysProc
    stdout: StdioCollector {
      onStreamFinished: root.capturedKey = this.text.trim()
    }
  }

  // Canonical form comes from keysmith-keys, never from QML, so the overlay
  // and the writer can never disagree about what key was pressed.
  function canonicalize(qtKey, qtMods) {
    keysProc.command = [root.pluginDir + "/keysmith-keys", "qt", String(qtKey), String(qtMods)]
    keysProc.running = true
  }

  function beginCapture() {
    var i = list.currentIndex
    if (i < 0 || i >= root.filtered.length)
      return
    root.selected = root.filtered[i]
    root.capturedKey = ""
    root.capturing = true
  }

  function cancelCapture() {
    root.capturing = false
    root.capturedKey = ""
    root.selected = null
    root.status = ""
  }

  Process {
    id: writeProc
    onExited: function (exitCode) {
      if (exitCode === 0) {
        root.cancelCapture()
        root.dismiss()
        return
      }
      root.status = exitCode === 2 ? "already taken - nothing written"
        : exitCode === 3 ? "config error - change rolled back"
        : exitCode === 4 ? "rollback failed - check bindings.lua"
        : "write failed (" + exitCode + ")"
    }
  }

  function commit() {
    if (!root.selected || !root.capturedKey)
      return
    root.status = "saving..."
    var cmd = [root.pluginDir + "/keysmith-write", root.capturedKey,
               root.selected.label, root.selected.action || ""]
    if (root.conflictFor(root.capturedKey))
      cmd.push("--replace")
    writeProc.command = cmd
    writeProc.running = true
  }

  Process {
    id: readProc
    command: [root.pluginDir + "/keysmith-read"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.rows = JSON.parse(this.text)
        } catch (e) {
          root.rows = []
        }
      }
    }
  }

  function conflictFor(canonicalKey) {
    if (!canonicalKey)
      return null
    for (var i = 0; i < root.rows.length; i++)
      if (root.rows[i].key === canonicalKey)
        return root.rows[i]
    return null
  }

  readonly property var filtered: {
    var q = root.filterText.toLowerCase()
    if (!q)
      return root.rows.slice(0, 200)
    return root.rows.filter(function (r) {
      return r.label.toLowerCase().indexOf(q) !== -1
    }).slice(0, 200)
  }

  function open(payloadJson) {
    root.filterText = ""
    root.selected = null
    root.capturing = false
    root.capturedKey = ""
    root.status = ""
    readProc.running = true
    root.opened = true
    Qt.callLater(function () {
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
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

        Column {
          visible: root.capturing || root.capturedKey.length > 0
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
              var c = root.conflictFor(root.capturedKey)
              if (!c)
                return "free — nothing else uses this\nEnter to save · Escape to cancel"
              return "taken by \"" + c.label + "\"\nEnter to replace it · Escape to cancel"
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

        ListView {
          id: list
          visible: !root.capturing && root.capturedKey.length === 0
          width: parent.width
          height: parent.height - Style.space(64)
          clip: true
          model: root.filtered
          currentIndex: 0
          keyNavigationEnabled: false

          delegate: Rectangle {
            width: ListView.view.width
            height: Style.space(26)
            color: ListView.isCurrentItem ? root.foreground : "transparent"
            opacity: ListView.isCurrentItem ? 0.12 : 1.0

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width * 0.6
              elide: Text.ElideRight
              text: modelData.label
              color: root.foreground
              opacity: modelData.rebindable ? 1.0 : 0.45
              font.family: root.fontFamily
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.key ? modelData.key : (modelData.source === "app" ? "not bound" : "")
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
            }
          }
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (root.capturing) {
            // Escape first, always. With the inhibitor active every other key
            // is being swallowed, so this is the only way out.
            if (event.key === Qt.Key_Escape) {
              root.cancelCapture()
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
            root.capturing = false
            event.accepted = true
            return
          }

          // Escape is handled before anything else. An exclusive keyboard
          // grab with no way out locks the user out of their session.
          if (event.key === Qt.Key_Escape) {
            if (root.capturedKey) {
              root.cancelCapture()
              event.accepted = true
              return
            }
            if (root.filterText)
              root.filterText = ""
            else
              root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.capturedKey.length === 0)
              root.beginCapture()
            else
              root.commit()
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
