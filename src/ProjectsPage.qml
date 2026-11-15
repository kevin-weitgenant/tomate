import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Projects: name, colour, default preset. Archive keeps history; delete
// removes the project and its sessions after asking.
Item {
    id: page
    property bool showArchived: false

    Shortcut { sequence: "N"; context: Qt.ApplicationShortcut; enabled: win.page === 2 && !win.typing && !win.modal; onActivated: editor.openFor(null) }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            Text { text: qsTr("Projects"); color: ui.bright; font.bold: true; font.pixelSize: 18 }
            Item { Layout.fillWidth: true }
            Btn { text: page.showArchived ? qsTr("Hide archived") : qsTr("Show archived"); onClicked: page.showArchived = !page.showArchived }
            Btn { text: qsTr("New"); kbd: "N"; primary: true; onClicked: editor.openFor(null) }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: backend.projects.filter(p => page.showArchived || !p.archived)
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: row
                required property var modelData
                width: ListView.view.width
                height: 54
                radius: ui.small
                readonly property bool selected: modelData.id === backend.projectId
                opacity: modelData.archived ? 0.55 : 1
                color: rowMouse.containsMouse ? ui.panel : ui.deep
                border.width: selected ? 2 : 1
                border.color: selected ? ui.accent : ui.line

                MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: editor.openFor(row.modelData) }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 16
                    Swatch { colorIndex: row.modelData.color; size: 14 }
                    Column {
                        Layout.fillWidth: true
                        Text { text: row.modelData.name; color: ui.bright; font.bold: true; elide: Text.ElideRight; width: parent.width }
                        Text {
                            text: row.modelData.archived ? qsTr("archived · history kept")
                                : qsTr("preset %1").arg(row.modelData.presetName || backend.presets[0].name)
                            color: ui.dim; font.pixelSize: 11
                        }
                    }
                    Column {
                        visible: page.width > 640
                        Text { text: qsTr("today"); color: ui.dim; font.pixelSize: 11; anchors.right: parent.right }
                        Text { text: row.modelData.todaySec ? win.hm(row.modelData.todaySec) : "—"; color: ui.bright; anchors.right: parent.right }
                    }
                    Column {
                        Layout.preferredWidth: 80
                        Text { text: qsTr("week"); color: ui.dim; font.pixelSize: 11; anchors.right: parent.right }
                        Text { text: row.modelData.weekSec ? win.hm(row.modelData.weekSec) : "—"; color: ui.bright; anchors.right: parent.right }
                    }
                    Column {
                        Layout.preferredWidth: 80
                        visible: page.width > 760
                        Text { text: qsTr("all time"); color: ui.dim; font.pixelSize: 11; anchors.right: parent.right }
                        Text { text: row.modelData.totalSec ? win.hm(row.modelData.totalSec) : "—"; color: ui.bright; anchors.right: parent.right }
                    }
                    Btn {
                        implicitHeight: 28
                        visible: !row.modelData.archived && !row.selected
                        text: qsTr("Use")
                        onClicked: backend.setProject(row.modelData.id)
                    }
                }
            }
        }
    }

    // New / edit -------------------------------------------------------------
    Sheet {
        id: editor
        property var project: null
        property int color: 0
        property int presetId: 0
        property bool confirmDelete: false
        title: project ? qsTr("Edit project") : qsTr("New project")

        function openFor(p) {
            project = p
            nameField.text = p ? p.name : ""
            color = p ? p.color : (backend.projects.length % theme.projectColors.length)
            presetId = p ? (p.presetId || 0) : (backend.presets.length ? backend.presets[0].id : 0)
            confirmDelete = false
            open()
        }
        function save() {
            const name = nameField.text.trim()
            if (!name) return
            if (project) backend.updateProject(project.id, name, color, presetId)
            else backend.createProject(name, color, presetId)
            close()
        }
        onOpened: nameField.input.forceActiveFocus()

        Field { id: nameField; width: parent.width; placeholder: qsTr("Project name"); onAccepted: editor.save() }

        Text { text: qsTr("Colour"); color: ui.dim; font.pixelSize: 11 }
        Flow {
            width: parent.width
            spacing: 8
            Repeater {
                model: theme.projectColors.length
                delegate: Rectangle {
                    required property int index
                    width: 26; height: 26
                    radius: Math.min(3, ui.radius)
                    color: "transparent"
                    border.width: 2
                    border.color: editor.color === index ? ui.accent : "transparent"
                    Swatch { anchors.centerIn: parent; colorIndex: index; size: 18 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: editor.color = index }
                }
            }
        }

        Text { text: qsTr("Default preset"); color: ui.dim; font.pixelSize: 11 }
        Flow {
            width: parent.width
            spacing: 6
            Repeater {
                model: backend.presets
                delegate: Btn {
                    required property var modelData
                    implicitHeight: 28
                    text: win.presetLabel(modelData)
                    checked: editor.presetId === modelData.id
                    onClicked: editor.presetId = modelData.id
                }
            }
        }

        RowLayout {
            width: parent.width
            spacing: 8
            Btn { text: editor.project ? qsTr("Save") : qsTr("Create"); kbd: "Enter"; primary: true; onClicked: editor.save() }
            Btn { text: qsTr("Cancel"); kbd: "Esc"; onClicked: editor.close() }
            Item { Layout.fillWidth: true }
            Btn {
                visible: editor.project !== null
                text: editor.project && editor.project.archived ? qsTr("Unarchive") : qsTr("Archive")
                onClicked: { backend.setArchived(editor.project.id, !editor.project.archived); editor.close() }
            }
        }
        Column {
            visible: editor.project !== null
            width: parent.width
            spacing: 8
            Rectangle { width: parent.width; height: 1; color: ui.line }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: editor.confirmDelete ? ui.red : ui.dim
                font.pixelSize: 11
                text: editor.confirmDelete
                      ? qsTr("Delete this project and its %n session(s)? This can't be undone. Archive keeps the history instead.", "", editor.project ? editor.project.sessions : 0)
                      : qsTr("Deleting removes its sessions from the calendar too.")
            }
            Btn {
                danger: true
                text: editor.confirmDelete ? qsTr("Yes, delete it") : qsTr("Delete project…")
                onClicked: {
                    if (!editor.confirmDelete) { editor.confirmDelete = true; return }
                    backend.deleteProject(editor.project.id)
                    editor.close()
                }
            }
        }
    }
}
