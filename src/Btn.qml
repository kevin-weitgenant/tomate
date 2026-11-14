import QtQuick

// A flat square button with an optional key hint, like the plan's mock-ups.
Rectangle {
    id: root
    property string text
    property string kbd
    property bool primary: false
    property bool danger: false
    property bool checked: false
    property bool enabledState: true
    signal clicked()

    implicitWidth: row.implicitWidth + 24
    implicitHeight: 34
    radius: ui.small
    opacity: enabledState ? 1 : 0.4
    color: primary ? (mouse.containsMouse ? Qt.lighter(ui.accent, 1.1) : ui.accent)
         : checked ? Qt.alpha(ui.accent, 0.14)
         : mouse.containsMouse ? ui.sel : ui.panel
    border.width: checked ? 2 : 1
    border.color: primary ? ui.accent : checked ? ui.accent : danger && mouse.containsMouse ? ui.red : ui.line

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.primary ? ui.onAccent : root.danger ? ui.red : root.checked ? ui.accent : ui.bright
            font.bold: root.primary
        }
        Rectangle {
            visible: root.kbd !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: kbdText.implicitWidth + 10
            height: kbdText.implicitHeight + 2
            color: "transparent"
            radius: Math.min(3, ui.radius)
            border.color: root.primary ? ui.onAccent : ui.line
            Text {
                id: kbdText
                anchors.centerIn: parent
                text: root.kbd
                font.pixelSize: 10
                color: root.primary ? ui.onAccent : ui.dim
            }
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
