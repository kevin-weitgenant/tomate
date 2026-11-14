import QtQuick

// A small key hint that appears beside a control on hover.
Rectangle {
    property string text
    anchors.left: parent.right
    anchors.leftMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    width: hintText.implicitWidth + 12
    height: hintText.implicitHeight + 6
    color: ui.panel
    border.color: ui.line
    radius: ui.small
    z: 100
    Text { id: hintText; anchors.centerIn: parent; text: parent.text; color: ui.bright; font.pixelSize: 11 }
}
