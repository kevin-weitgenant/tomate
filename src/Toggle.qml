import QtQuick
import QtQuick.Layouts

// A label with a square on/off switch on the right.
RowLayout {
    id: root
    property string label
    property bool checked: false
    signal toggled(bool checked)
    spacing: 8
    Text { text: root.label; color: ui.text; Layout.fillWidth: true; elide: Text.ElideRight }
    Rectangle {
        implicitWidth: 40; implicitHeight: 20
        radius: ui.small
        color: root.checked ? Qt.alpha(ui.accent, 0.18) : ui.panel
        border.color: root.checked ? ui.accent : ui.line
        Rectangle {
            width: 12; height: 12
            radius: Math.min(2, ui.radius)
            y: 4
            x: root.checked ? parent.width - width - 4 : 4
            color: root.checked ? ui.accent : ui.dim
            Behavior on x { NumberAnimation { duration: 120 } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggled(!root.checked) }
    }
}
