import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "sinkeat.keysmith"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "⌨"
    tooltipText: "Keysmith — manage shortcuts"

    onPressed: function (button) {
      if (button === Qt.LeftButton && root.bar)
        root.bar.run("omarchy-shell shell toggle sinkeat.keysmith")
    }
  }
}
