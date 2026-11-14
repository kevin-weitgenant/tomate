import QtQuick
import QtQuick.Layouts

// A label with − value + on the right. The value can also be typed: click it,
// type any number, press Enter. Up and Down step it while it has focus.
RowLayout {
    id: root
    property string label
    property real value: 0
    property real step: 1
    property real from: 1
    property real to: 600
    property string suffix: ""
    property bool decimals: true
    signal edited(real value)

    function commit(v) {
        v = Math.min(root.to, Math.max(root.from, v))
        if (!root.decimals) v = Math.round(v)
        v = Math.round(v * 10) / 10
        if (v !== root.value) root.edited(v)
        valueInput.text = win.minutes(root.value)
    }

    spacing: 8
    Text { text: root.label; color: ui.text; Layout.fillWidth: true; elide: Text.ElideRight }
    Rectangle {
        implicitWidth: 26; implicitHeight: 26
        radius: ui.small
        color: minusMouse.containsMouse ? ui.sel : "transparent"
        border.color: ui.line
        Text { anchors.centerIn: parent; text: "−"; color: ui.accent; font.bold: true }
        MouseArea { id: minusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.commit(root.value - root.step) }
    }
    Rectangle {
        implicitWidth: 86; implicitHeight: 28
        color: valueInput.activeFocus ? ui.deep : "transparent"
        border.color: valueInput.activeFocus ? ui.accent : "transparent"
        border.width: valueInput.activeFocus ? 2 : 0
        radius: ui.small
        RowLayout {
            anchors.centerIn: parent
            spacing: 4
            TextInput {
                id: valueInput
                Component.onCompleted: text = win.minutes(root.value)
                color: ui.bright
                font.bold: true
                selectByMouse: true
                horizontalAlignment: TextInput.AlignRight
                validator: DoubleValidator { bottom: root.from; top: root.to; decimals: root.decimals ? 1 : 0; notation: DoubleValidator.StandardNotation }
                onEditingFinished: root.commit(parseFloat(text.replace(",", ".")) || root.value)
                Keys.onUpPressed: root.commit(root.value + root.step)
                Keys.onDownPressed: root.commit(root.value - root.step)
                Keys.onEscapePressed: { text = win.minutes(root.value); focus = false }
            }
            Text { text: root.suffix; color: ui.dim; visible: root.suffix !== "" }
        }
    }
    Rectangle {
        implicitWidth: 26; implicitHeight: 26
        radius: ui.small
        color: plusMouse.containsMouse ? ui.sel : "transparent"
        border.color: ui.line
        Text { anchors.centerIn: parent; text: "+"; color: ui.accent; font.bold: true }
        MouseArea { id: plusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.commit(root.value + root.step) }
    }
    onValueChanged: if (!valueInput.activeFocus) valueInput.text = win.minutes(value)
}
