import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Fix or add one block: project, start, end, note.
Sheet {
    id: root
    property var session: null      // null when adding
    property real start: 0
    property real end: 0
    property int projectId: 0
    property string error: ""
    readonly property bool running: session !== null && session.running

    title: session === null ? qsTr("Add time") : running ? qsTr("Running session") : qsTr("Edit session")

    function openFor(s) {
        session = s
        start = s.start
        end = s.running ? backend.nowSec : s.end
        projectId = s.projectId
        note.text = s.note
        fill()
    }
    function openNew(a, b) {
        session = null
        start = a
        end = b
        projectId = backend.projectId
        note.text = ""
        fill()
    }
    function fill() {
        startField.text = win.timeOf(start)
        endField.text = win.timeOf(end)
        error = ""
        open()
    }
    // "9:5", "0905" and "09:05" all mean 09:05 on the block's own day.
    function parse(text, base) {
        const digits = text.replace(/[^0-9:]/g, "")
        let h, m
        if (digits.includes(":")) [h, m] = digits.split(":").map(Number)
        else if (digits.length >= 3) { h = Number(digits.slice(0, -2)); m = Number(digits.slice(-2)) }
        else { h = Number(digits); m = 0 }
        if (isNaN(h) || isNaN(m) || h > 24 || m > 59) return NaN
        const d = new Date(base * 1000)
        d.setHours(h, m, 0, 0)
        return d.getTime() / 1000
    }
    function save() {
        let a = parse(startField.text, start), b = parse(endField.text, start)
        if (isNaN(a) || isNaN(b)) { error = qsTr("Times look like 09:30."); return }
        if (b <= a) b += 86400   // an end before the start means it ran past midnight
        if (b - a > 16 * 3600) { error = qsTr("That's longer than 16 hours."); return }
        if (session === null) backend.addSession(projectId, a, b, note.text)
        else backend.updateSession(session.id, projectId, a, b, note.text)
        close()
    }

    Text {
        text: Qt.locale().dayName(new Date(root.start * 1000).getDay()) + " " + Qt.formatDate(new Date(root.start * 1000), "d MMM yyyy")
              + (root.session && !root.session.completed && !root.running ? " · " + qsTr("stopped early") : "")
              + (root.session && root.session.kind === "manual" ? " · " + qsTr("added by hand") : "")
        color: ui.dim
        font.pixelSize: 11
    }

    Flow {
        width: parent.width
        spacing: 6
        Repeater {
            model: backend.projects.filter(p => !p.archived || p.id === root.projectId)
            delegate: Btn {
                required property var modelData
                implicitHeight: 28
                text: "■ " + modelData.name
                checked: root.projectId === modelData.id
                onClicked: root.projectId = modelData.id
            }
        }
    }

    RowLayout {
        width: parent.width
        spacing: 12
        Text { text: qsTr("from"); color: ui.dim }
        Field { id: startField; Layout.preferredWidth: 80; enabled: !root.running; textColor: root.running ? ui.dim : ui.bright; tabTarget: endField.input; onAccepted: root.save() }
        Text { text: qsTr("to"); color: ui.dim }
        Field { id: endField; Layout.preferredWidth: 80; enabled: !root.running; textColor: root.running ? ui.dim : ui.bright; tabTarget: note.input; onAccepted: root.save() }
        Item { Layout.fillWidth: true }
    }
    Field { id: note; width: parent.width; placeholder: qsTr("Note"); onAccepted: root.save() }
    Text { visible: root.error !== ""; text: root.error; color: ui.red }

    RowLayout {
        width: parent.width
        spacing: 8
        Btn { text: root.session === null ? qsTr("Add") : qsTr("Save"); kbd: "Enter"; primary: true; onClicked: root.save() }
        Btn { text: qsTr("Cancel"); kbd: "Esc"; onClicked: root.close() }
        Item { Layout.fillWidth: true }
        Btn {
            visible: root.session !== null
            danger: true
            text: root.running ? qsTr("Stop and delete") : qsTr("Delete")
            onClicked: { backend.deleteSession(root.session.id); root.close() }
        }
    }
}
