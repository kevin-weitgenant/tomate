import QtQuick

// A one-line text input drawn as a single underline, accent when focused.
FocusScope {
    id: root
    property alias text: input.text
    property alias placeholder: placeholderText.text
    property alias validator: input.validator
    property alias horizontalAlignment: input.horizontalAlignment
    property alias font: input.font
    property alias input: input
    property color textColor: ui.bright
    property Item tabTarget: null
    signal accepted()
    signal editingFinished()
    signal escaped()
    signal stepped(int delta)

    implicitWidth: 240
    implicitHeight: input.implicitHeight + 12

    TextInput {
        id: input
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        focus: true
        color: root.textColor
        selectionColor: ui.sel
        selectedTextColor: ui.bright
        selectByMouse: true
        clip: true
        onAccepted: root.accepted()
        onEditingFinished: root.editingFinished()
        KeyNavigation.tab: root.tabTarget
        Keys.onUpPressed: event => { root.stepped(1); event.accepted = true }
        Keys.onDownPressed: event => { root.stepped(-1); event.accepted = true }
        Keys.onEscapePressed: event => { input.focus = false; root.escaped(); event.accepted = false }
    }
    Text {
        id: placeholderText
        anchors.fill: input
        horizontalAlignment: input.horizontalAlignment
        verticalAlignment: Text.AlignVCenter
        visible: input.text === "" && !input.activeFocus
        color: ui.dim
        font: input.font
        elide: Text.ElideRight
    }
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: input.activeFocus ? 2 : 1
        color: input.activeFocus ? ui.accent : ui.line
    }
}
