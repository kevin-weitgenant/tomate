import QtQuick
import QtQuick.Layouts

// Every shortcut, toggled with ?.
Rectangle {
    id: root
    color: Qt.alpha(ui.deep, 0.92)
    MouseArea { anchors.fill: parent; onClicked: win.helpVisible = false }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(640, parent.width - 40)
        height: grid.implicitHeight + 70
        color: ui.bg
        border.color: ui.accent
        border.width: 2
        radius: ui.radius
        MouseArea { anchors.fill: parent }

        Text {
            x: 20; y: 16
            text: qsTr("Keyboard")
            color: ui.bright
            font.bold: true
            font.pixelSize: 15
        }
        GridLayout {
            id: grid
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20; topMargin: 50 }
            columns: 2
            columnSpacing: 28
            rowSpacing: 8
            Repeater {
                model: [
                    ["Space", qsTr("start / pause / resume")],
                    ["S", qsTr("skip to the next phase")],
                    ["X", qsTr("stop and log what was done")],
                    ["E", qsTr("custom times for this cycle")],
                    ["P", qsTr("switch project")],
                    ["1 – 4", qsTr("Timer · Calendar · Projects · Presets")],
                    ["← →", qsTr("previous / next (calendar)")],
                    ["T", qsTr("today (calendar)")],
                    ["D W M", qsTr("day / week / month (calendar)")],
                    ["N", qsTr("new project or preset")],
                    ["?", qsTr("this help")],
                    ["Q", qsTr("quit")]
                ]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 22
                        color: ui.panel
                        border.color: ui.line
                        radius: Math.min(3, ui.radius)
                        Text { anchors.centerIn: parent; text: modelData[0]; color: ui.bright; font.pixelSize: 11 }
                    }
                    Text { text: modelData[1]; color: ui.text; Layout.fillWidth: true; elide: Text.ElideRight }
                }
            }
        }
    }
}
