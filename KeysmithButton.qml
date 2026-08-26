import QtQuick
import qs.Commons

Rectangle {
  id: button

  required property string label
  property bool primary: false
  signal triggered()

  height: Style.space(30)
  color: button.primary
    ? Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.12)
    : "transparent"
  border.color: Color.menu.border
  border.width: 1
  opacity: button.enabled ? 1.0 : 0.5

  Text {
    anchors.centerIn: parent
    text: button.label
    color: Color.menu.text
    font.family: Style.font.menuFamily
  }

  MouseArea {
    anchors.fill: parent
    enabled: button.enabled
    onClicked: button.triggered()
  }
}
