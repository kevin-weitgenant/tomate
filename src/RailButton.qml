import QtQuick

// One entry in the left rail: an icon over a label, accent-bordered when active.
Rectangle {
    id: root
    property string icon
    property string label
    property string hint
    property bool active: false
    signal clicked()

    implicitHeight: 58
    radius: ui.small
    color: active ? Qt.alpha(ui.accent, 0.14) : mouse.containsMouse ? ui.panel : "transparent"
    border.width: active ? 2 : 1
    border.color: active ? ui.accent : mouse.containsMouse ? ui.line : "transparent"

    Column {
        anchors.centerIn: parent
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon
            font.pixelSize: 20
            color: root.active ? ui.accent : ui.text
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            font.pixelSize: 10
            color: root.active ? ui.accent : ui.dim
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    ToolTipHint { visible: mouse.containsMouse && root.hint !== ""; text: root.hint }
}
