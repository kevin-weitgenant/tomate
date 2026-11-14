import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Fuzzy project switcher (P): type to filter, arrows to move, Enter to pick.
Sheet {
    id: root
    title: qsTr("Switch project")
    property int current: 0

    readonly property var matches: {
        const q = search.text.toLowerCase().trim()
        const out = []
        for (const p of backend.projects) {
            if (p.archived) continue
            // Letters in order, anywhere in the name: "sp" finds "Side project".
            let i = 0
            for (const ch of p.name.toLowerCase()) if (i < q.length && ch === q[i]) i++
            if (i === q.length) out.push(p)
        }
        return out
    }
    function pick(p) {
        if (p) backend.setProject(p.id)
        root.close()
    }

    onOpened: { search.text = ""; current = 0; search.input.forceActiveFocus() }
    onMatchesChanged: current = 0

    Field {
        id: search
        width: parent.width
        placeholder: qsTr("Type to filter…")
        onAccepted: root.pick(root.matches[root.current])
        onStepped: delta => root.current = Math.max(0, Math.min(root.matches.length - 1, root.current - delta))
    }
    Column {
        width: parent.width
        spacing: 4
        Repeater {
            model: root.matches
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: parent.width
                height: 36
                radius: ui.small
                color: index === root.current ? Qt.alpha(ui.accent, 0.14) : rowMouse.containsMouse ? ui.panel : "transparent"
                border.color: index === root.current ? ui.accent : "transparent"
                border.width: index === root.current ? 2 : 0
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10
                    Swatch { colorIndex: modelData.color }
                    Text { text: modelData.name; color: ui.bright; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: modelData.id === backend.projectId ? qsTr("current") : win.hm(modelData.todaySec); color: ui.dim; font.pixelSize: 11 }
                }
                MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pick(modelData) }
            }
        }
        Text {
            visible: root.matches.length === 0
            text: qsTr("No project matches. Create one on the Projects screen (3, then N).")
            color: ui.dim
            wrapMode: Text.WordWrap
            width: parent.width
        }
    }
}
