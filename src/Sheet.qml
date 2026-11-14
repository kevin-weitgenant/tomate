import QtQuick
import QtQuick.Controls

// A modal panel in the app's style: accent border, square corners, centred.
// While one is open the single-key shortcuts stand aside.
Popup {
    id: root
    property string title
    default property alias content: body.data

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    padding: 18
    width: Math.min(440, parent ? parent.width - 40 : 440)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: win.popups++
    onClosed: win.popups = Math.max(0, win.popups - 1)

    background: Rectangle {
        color: ui.bg
        border.color: ui.accent
        border.width: 2
        radius: ui.radius
    }
    Overlay.modal: Rectangle { color: Qt.alpha(ui.deep, 0.6) }

    contentItem: Column {
        spacing: 12
        Text {
            visible: root.title !== ""
            text: root.title
            color: ui.bright
            font.bold: true
            font.pixelSize: 15
        }
        Column {
            id: body
            width: parent.width
            spacing: 12
        }
    }
}
