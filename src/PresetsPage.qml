import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Presets: any focus, break and long-break length, how often the long break
// comes, and what starts on its own. Edits save as you make them.
Item {
    id: page
    property int selectedId: backend.presets.length ? backend.presets[0].id : 0
    readonly property var selected: {
        for (const p of backend.presets) if (p.id === selectedId) return p
        return backend.presets.length ? backend.presets[0] : null
    }
    function update(key, value) {
        const p = Object.assign({}, page.selected)
        p[key] = value
        backend.updatePreset(p.id, p)
    }
    function create() {
        page.selectedId = backend.createPreset({ name: qsTr("New preset"), focusMin: 30, shortMin: 5, longMin: 15, every: 4, autoBreaks: true, autoFocus: false })
        nameField.input.forceActiveFocus()
        nameField.input.selectAll()
    }

    Shortcut { sequence: "N"; context: Qt.ApplicationShortcut; enabled: win.page === 3 && !win.typing && !win.modal; onActivated: page.create() }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 48
        clip: true
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: col
            x: 24; y: 24
            width: page.width - 48
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Text { text: qsTr("Presets"); color: ui.bright; font.bold: true; font.pixelSize: 18 }
                Item { Layout.fillWidth: true }
                Btn { text: qsTr("New preset"); kbd: "N"; primary: true; onClicked: page.create() }
            }

            // Cards, each with one full cycle drawn to scale.
            GridLayout {
                Layout.fillWidth: true
                columns: Math.max(1, Math.floor(col.width / 230))
                columnSpacing: 8
                rowSpacing: 8
                Repeater {
                    model: backend.presets
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 84
                        radius: ui.small
                        readonly property bool sel: modelData.id === page.selectedId
                        color: cardMouse.containsMouse ? ui.panel : ui.deep
                        border.width: sel ? 2 : 1
                        border.color: sel ? ui.accent : ui.line
                        MouseArea { id: cardMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.selectedId = card.modelData.id }
                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4
                            Text { text: card.modelData.name; color: ui.bright; font.bold: true; elide: Text.ElideRight; width: parent.width }
                            Text {
                                text: qsTr("%1 · %2 · %3 every %4").arg(win.minutes(card.modelData.focusMin)).arg(win.minutes(card.modelData.shortMin))
                                        .arg(win.minutes(card.modelData.longMin)).arg(card.modelData.every)
                                color: ui.dim; font.pixelSize: 11
                            }
                            Item { width: 1; height: 4 }
                            CycleBar { width: parent.width; height: 14; preset: card.modelData }
                        }
                    }
                }
            }

            Row {
                spacing: 16
                Repeater {
                    model: [[ui.accent, qsTr("focus")], [ui.green, qsTr("short break")], [ui.magenta, qsTr("long break")]]
                    delegate: Row {
                        required property var modelData
                        spacing: 6
                        Rectangle { width: 10; height: 10; color: modelData[0]; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData[1]; color: ui.dim; font.pixelSize: 11 }
                    }
                }
            }

            // Editor for the selected preset.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: editor.implicitHeight + 32
                visible: page.selected !== null
                color: ui.deep
                border.color: ui.line
                radius: ui.small

                ColumnLayout {
                    id: editor
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Field {
                            id: nameField
                            Layout.fillWidth: true
                            font.bold: true
                            font.pixelSize: 15
                            // Filled in by hand, not bound, so a data refresh can't
                            // overwrite a name that is being typed.
                            Component.onCompleted: text = page.selected ? page.selected.name : ""
                            Connections {
                                target: page
                                function onSelectedChanged() {
                                    if (!nameField.input.activeFocus) nameField.text = page.selected ? page.selected.name : ""
                                }
                            }
                            onEditingFinished: if (text.trim() && page.selected && text !== page.selected.name) page.update("name", text.trim())
                            onAccepted: nameField.input.focus = false
                        }
                        Btn {
                            danger: true
                            text: qsTr("Delete")
                            enabledState: backend.presets.length > 1
                            onClicked: {
                                const id = page.selected.id
                                page.selectedId = backend.presets[0].id === id ? backend.presets[1].id : backend.presets[0].id
                                backend.deletePreset(id)
                            }
                        }
                    }
                    Text {
                        visible: page.selected && page.selected.projects > 0
                        text: page.selected ? qsTr("Default for %n project(s).", "", page.selected.projects) : ""
                        color: ui.dim; font.pixelSize: 11
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: col.width > 700 ? 2 : 1
                        columnSpacing: 36
                        rowSpacing: 6
                        Stepper { Layout.fillWidth: true; label: qsTr("Focus"); suffix: qsTr("min"); from: 0.5; to: 600
                                  value: page.selected ? page.selected.focusMin : 0; onEdited: v => page.update("focusMin", v) }
                        Toggle { Layout.fillWidth: true; label: qsTr("Start breaks automatically")
                                 checked: page.selected ? page.selected.autoBreaks : false; onToggled: c => page.update("autoBreaks", c) }
                        Stepper { Layout.fillWidth: true; label: qsTr("Short break"); suffix: qsTr("min"); from: 0.5; to: 600
                                  value: page.selected ? page.selected.shortMin : 0; onEdited: v => page.update("shortMin", v) }
                        Toggle { Layout.fillWidth: true; label: qsTr("Start next focus automatically")
                                 checked: page.selected ? page.selected.autoFocus : false; onToggled: c => page.update("autoFocus", c) }
                        Stepper { Layout.fillWidth: true; label: qsTr("Long break"); suffix: qsTr("min"); from: 0.5; to: 600
                                  value: page.selected ? page.selected.longMin : 0; onEdited: v => page.update("longMin", v) }
                        Item { implicitHeight: 1 }
                        Stepper { Layout.fillWidth: true; label: qsTr("Long break every"); suffix: qsTr("rounds"); from: 1; to: 99; decimals: false
                                  value: page.selected ? page.selected.every : 0; onEdited: v => page.update("every", v) }
                    }
                }
            }

            // App settings.
            Text { Layout.topMargin: 10; text: qsTr("Settings"); color: ui.bright; font.bold: true; font.pixelSize: 15 }
            GridLayout {
                Layout.fillWidth: true
                columns: col.width > 700 ? 2 : 1
                columnSpacing: 36
                Stepper { Layout.fillWidth: true; label: qsTr("Daily goal"); suffix: qsTr("h"); from: 0; to: 24; step: 0.5
                          value: backend.dailyGoalMin / 60; onEdited: v => backend.setDailyGoalMin(Math.round(v * 60)) }
                Toggle { Layout.fillWidth: true; label: qsTr("Sound when a phase ends"); checked: backend.sound; onToggled: c => backend.setSound(c) }
            }
            Text {
                Layout.fillWidth: true
                text: qsTr("Everything is stored on this computer in %1").arg(backend.dbPath)
                color: ui.dim; font.pixelSize: 11; wrapMode: Text.WrapAnywhere
            }
        }
    }
}
