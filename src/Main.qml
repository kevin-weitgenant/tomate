import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1040
    height: 720
    minimumWidth: 720
    minimumHeight: 560
    visible: true
    title: "Tomate"
    color: ui.bg

    Material.theme: theme.dark ? Material.Dark : Material.Light
    Material.accent: theme.accent
    Material.background: ui.bg
    Material.foreground: ui.text
    Material.roundedScale: theme.radius

    // The palette every file draws with, straight from the Omarchy theme.
    readonly property QtObject ui: QtObject {
        readonly property color bg: theme.colors.background
        readonly property color deep: theme.colors.dark_background
        readonly property color panel: theme.colors.lighter_background
        readonly property color sel: theme.colors.selection
        readonly property color line: theme.colors.muted
        readonly property color text: theme.colors.foreground
        readonly property color bright: theme.colors.bright_foreground
        readonly property color dim: theme.colors.dark_foreground
        readonly property color accent: theme.accent
        readonly property color onAccent: theme.accentForeground
        readonly property color green: theme.colors.green
        readonly property color red: theme.colors.red
        readonly property color yellow: theme.colors.yellow
        readonly property color magenta: theme.colors.magenta
        readonly property int radius: theme.radius
        readonly property int small: Math.min(4, theme.radius)
    }

    property int page: 0
    property bool helpVisible: false
    // Single-letter shortcuts must not fire while a text field has focus.
    readonly property bool typing: activeFocusItem !== null && activeFocusItem.hasOwnProperty("cursorPosition")
    property int popups: 0
    readonly property bool modal: helpVisible || popups > 0

    function projectColor(index) {
        const list = theme.projectColors
        return list.length ? list[((index % list.length) + list.length) % list.length] : ui.accent
    }
    function phaseColor(phase) {
        return phase === "focus" ? ui.accent : phase === "short" ? ui.green : ui.magenta
    }
    function phaseName(phase) {
        return phase === "focus" ? qsTr("Focus") : phase === "short" ? qsTr("Short break") : qsTr("Long break")
    }
    function pad(n) { return (n < 10 ? "0" : "") + n }
    function clock(sec) {
        sec = Math.max(0, Math.round(sec))
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s)
    }
    function hm(sec) {
        sec = Math.max(0, Math.round(sec))
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60)
        return h > 0 ? qsTr("%1h %2m").arg(h).arg(pad(m)) : qsTr("%1m").arg(m)
    }
    function minutes(v) {
        // 25 → "25", 0.5 → "0.5": presets are whole minutes unless typed otherwise.
        return Number.isInteger(v) ? String(v) : v.toFixed(1)
    }
    // "Classic 25/5", or "Focus only 50" for a preset without breaks.
    function presetLabel(p) {
        return p.name + " " + minutes(p.focusMin) + (p.shortMin > 0 ? "/" + minutes(p.shortMin) : "")
    }
    function timeOf(sec) {
        return Qt.formatTime(new Date(sec * 1000), "HH:mm")
    }
    function project(id) {
        for (const p of backend.projects) if (p.id === id) return p
        return null
    }

    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; enabled: !win.typing; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Esc"; context: Qt.ApplicationShortcut; enabled: win.helpVisible; onActivated: win.helpVisible = false }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; enabled: !win.typing; onActivated: Qt.quit() }
    Shortcut { sequences: ["1"]; context: Qt.ApplicationShortcut; enabled: !win.typing && !win.modal; onActivated: win.page = 0 }
    Shortcut { sequences: ["2"]; context: Qt.ApplicationShortcut; enabled: !win.typing && !win.modal; onActivated: win.page = 1 }
    Shortcut { sequences: ["3"]; context: Qt.ApplicationShortcut; enabled: !win.typing && !win.modal; onActivated: win.page = 2 }
    Shortcut { sequences: ["4"]; context: Qt.ApplicationShortcut; enabled: !win.typing && !win.modal; onActivated: win.page = 3 }
    // The timer keys work from every screen.
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; enabled: !win.typing && !win.modal; onActivated: backend.toggle() }
    Shortcut { sequence: "S"; context: Qt.ApplicationShortcut; enabled: !win.typing && !win.modal; onActivated: backend.skip() }
    Shortcut { sequence: "X"; context: Qt.ApplicationShortcut; enabled: !win.typing && !win.modal; onActivated: backend.stop() }

    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Rail ----------------------------------------------------------
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 76
                color: ui.deep
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: ui.line }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    Repeater {
                        model: [
                            { icon: "◔", label: qsTr("Timer") },
                            { icon: "▤", label: qsTr("Calendar") },
                            { icon: "▦", label: qsTr("Projects") },
                            { icon: "≡", label: qsTr("Presets") }
                        ]
                        delegate: RailButton {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            icon: modelData.icon
                            label: modelData.label
                            hint: String(index + 1)
                            active: win.page === index
                            onClicked: win.page = index
                        }
                    }
                    Item { Layout.fillHeight: true }
                    // A tiny live timer, so other screens still show it.
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        visible: win.page !== 0 && !backend.idle
                        text: backend.waiting ? "··" : win.clock(backend.remainingSec)
                        color: backend.paused ? ui.dim : win.phaseColor(backend.phase)
                        font.bold: true
                    }
                    RailButton {
                        Layout.fillWidth: true
                        icon: "?"
                        label: qsTr("Keys")
                        onClicked: win.helpVisible = true
                    }
                }
            }

            // Pages ---------------------------------------------------------
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.page
                TimerPage {}
                CalendarPage {}
                ProjectsPage {}
                PresetsPage {}
            }
        }

        Rectangle {
            visible: dbError !== ""
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 34
            color: ui.red
            Text {
                anchors.centerIn: parent
                color: ui.bg
                text: qsTr("Can't open the database: %1").arg(dbError)
            }
        }

        HelpOverlay { anchors.fill: parent; visible: win.helpVisible }
    }
}
