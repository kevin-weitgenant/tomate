import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Where the work happened: one block per focus session, coloured by project,
// in a day or week grid, or a month heatmap. Click a block to fix it,
// double-click empty time to add time you worked away from the computer.
Item {
    id: page
    property string view: "week"           // day, week or month
    property date anchor: startOfDay(new Date())
    readonly property int hourHeight: 52
    readonly property int days: view === "day" ? 1 : 7

    function startOfDay(d) { const x = new Date(d); x.setHours(0, 0, 0, 0); return x }
    function addDays(d, n) { const x = new Date(d); x.setDate(x.getDate() + n); return startOfDay(x) }
    function monday(d) { return addDays(d, -((d.getDay() + 6) % 7)) }
    function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate() }

    readonly property date rangeStart: view === "week" ? monday(anchor)
                                     : view === "month" ? new Date(anchor.getFullYear(), anchor.getMonth(), 1)
                                     : startOfDay(anchor)
    readonly property date rangeEnd: view === "month" ? new Date(anchor.getFullYear(), anchor.getMonth() + 1, 1)
                                   : addDays(rangeStart, days)
    readonly property real fromSec: rangeStart.getTime() / 1000
    readonly property real toSec: rangeEnd.getTime() / 1000

    // Re-read whenever the range moves or anything is saved.
    readonly property var sessions: { backend.revision; return backend.sessions(fromSec, toSec) }
    readonly property var totals: {
        const per = {}
        let total = 0
        for (const s of sessions) {
            const sec = s.running ? s.durationSec + (backend.nowSec - s.end) : s.durationSec
            per[s.projectId] = per[s.projectId] || { id: s.projectId, name: s.project, color: s.color, sec: 0 }
            per[s.projectId].sec += sec
            total += sec
        }
        return { total: total, list: Object.values(per).sort((a, b) => b.sec - a.sec), count: sessions.length }
    }

    function step(n) {
        if (view === "month") anchor = new Date(anchor.getFullYear(), anchor.getMonth() + n, 1)
        else anchor = addDays(anchor, n * days)
    }
    function title() {
        if (view === "month") return Qt.locale().standaloneMonthName(anchor.getMonth()) + " " + anchor.getFullYear()
        if (view === "day") return Qt.locale().dayName(rangeStart.getDay()) + " " + Qt.formatDate(rangeStart, "d MMM yyyy")
        const last = addDays(rangeStart, 6)
        return Qt.formatDate(rangeStart, rangeStart.getMonth() === last.getMonth() ? "d" : "d MMM") + " – " + Qt.formatDate(last, "d MMM yyyy")
    }
    function scrollToMorning() {
        let first = 7
        for (const s of sessions) first = Math.min(first, new Date(s.start * 1000).getHours())
        grid.contentY = Math.max(0, (first - 0.5) * hourHeight)
    }

    readonly property bool keysOn: win.page === 1 && !win.typing && !win.modal
    Shortcut { sequence: "Left"; context: Qt.ApplicationShortcut; enabled: page.keysOn; onActivated: page.step(-1) }
    Shortcut { sequence: "Right"; context: Qt.ApplicationShortcut; enabled: page.keysOn; onActivated: page.step(1) }
    Shortcut { sequence: "T"; context: Qt.ApplicationShortcut; enabled: page.keysOn; onActivated: page.anchor = page.startOfDay(new Date()) }
    Shortcut { sequence: "D"; context: Qt.ApplicationShortcut; enabled: page.keysOn; onActivated: page.view = "day" }
    Shortcut { sequence: "W"; context: Qt.ApplicationShortcut; enabled: page.keysOn; onActivated: page.view = "week" }
    Shortcut { sequence: "M"; context: Qt.ApplicationShortcut; enabled: page.keysOn; onActivated: page.view = "month" }

    Component.onCompleted: scrollToMorning()
    onViewChanged: if (view !== "month") Qt.callLater(scrollToMorning)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        // Header -----------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text { text: page.title(); color: ui.bright; font.bold: true; font.pixelSize: 18; Layout.rightMargin: 10 }
            Btn { text: "◀"; onClicked: page.step(-1) }
            Btn { text: qsTr("Today"); kbd: "T"; onClicked: page.anchor = page.startOfDay(new Date()) }
            Btn { text: "▶"; onClicked: page.step(1) }
            Item { Layout.fillWidth: true }
            Btn { text: qsTr("Day"); kbd: "D"; checked: page.view === "day"; onClicked: page.view = "day" }
            Btn { text: qsTr("Week"); kbd: "W"; checked: page.view === "week"; onClicked: page.view = "week" }
            Btn { text: qsTr("Month"); kbd: "M"; checked: page.view === "month"; onClicked: page.view = "month" }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 20

            // Day / week grid --------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                visible: page.view !== "month"

                Row {
                    Layout.fillWidth: true
                    Item { width: 44; height: 1 }
                    Repeater {
                        model: page.days
                        delegate: Column {
                            required property int index
                            readonly property date day: page.addDays(page.rangeStart, index)
                            readonly property bool today: page.sameDay(day, new Date())
                            width: (grid.width - 44) / page.days
                            bottomPadding: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.locale().dayName(parent.day.getDay(), Locale.ShortFormat)
                                color: parent.today ? ui.accent : ui.dim
                                font.pixelSize: 11
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 30; height: 24
                                radius: ui.small
                                color: parent.today ? ui.accent : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.parent.day.getDate()
                                    color: parent.parent.today ? ui.onAccent : ui.bright
                                    font.bold: true
                                }
                            }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: ui.line }

                Flickable {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: 24 * page.hourHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}

                    // Hour lines and labels.
                    Repeater {
                        model: 24
                        delegate: Item {
                            required property int index
                            y: index * page.hourHeight
                            width: grid.width
                            height: page.hourHeight
                            Text { x: 4; y: -7; text: index === 0 ? "" : win.pad(index) + ":00"; color: ui.dim; font.pixelSize: 10 }
                            Rectangle { x: 44; width: parent.width - 44; height: 1; color: ui.line; opacity: 0.45 }
                        }
                    }

                    Row {
                        x: 44
                        Repeater {
                            model: page.days
                            delegate: Rectangle {
                                id: dayCol
                                required property int index
                                readonly property date day: page.addDays(page.rangeStart, index)
                                readonly property real dayStart: day.getTime() / 1000
                                readonly property real dayEnd: page.addDays(day, 1).getTime() / 1000
                                readonly property bool today: page.sameDay(day, new Date())
                                width: (grid.width - 44) / page.days
                                height: 24 * page.hourHeight
                                color: today ? Qt.alpha(ui.accent, 0.05) : "transparent"
                                Rectangle { width: 1; height: parent.height; color: ui.line; opacity: 0.6 }

                                // Double-click empty time: add a manual block there.
                                MouseArea {
                                    anchors.fill: parent
                                    onDoubleClicked: mouse => {
                                        const quarter = Math.floor(mouse.y / page.hourHeight * 4)
                                        const start = dayCol.dayStart + quarter * 900
                                        editor.openNew(start, start + 1800)
                                    }
                                }

                                Repeater {
                                    model: page.sessions.filter(s => s.start < dayCol.dayEnd && (s.running ? backend.nowSec : s.end) > dayCol.dayStart)
                                    delegate: Rectangle {
                                        id: block
                                        required property var modelData
                                        readonly property real a: Math.max(modelData.start, dayCol.dayStart)
                                        readonly property real b: Math.min(modelData.running ? backend.nowSec : modelData.end, dayCol.dayEnd)
                                        readonly property color tint: win.projectColor(modelData.color)
                                        x: 3
                                        width: dayCol.width - 6
                                        y: (a - dayCol.dayStart) / 3600 * page.hourHeight
                                        height: Math.max(4, (b - a) / 3600 * page.hourHeight - 1)
                                        radius: Math.min(3, ui.radius)
                                        color: Qt.alpha(tint, blockMouse.containsMouse ? 0.32 : 0.2)
                                        border.width: modelData.running || !modelData.completed ? 1 : 0
                                        border.color: tint
                                        clip: true
                                        Rectangle { width: 3; height: parent.height; color: block.tint }
                                        Column {
                                            x: 7; y: 2
                                            width: parent.width - 10
                                            Text {
                                                width: parent.width
                                                text: block.modelData.project + (block.modelData.running ? " · " + qsTr("now") : "")
                                                color: block.tint
                                                font.pixelSize: 11
                                                font.bold: true
                                                elide: Text.ElideRight
                                                visible: block.height > 14
                                            }
                                            Text {
                                                width: parent.width
                                                text: win.timeOf(block.modelData.start) + "–" + win.timeOf(block.b)
                                                color: ui.text
                                                font.pixelSize: 10
                                                visible: block.height > 30
                                            }
                                            Text {
                                                width: parent.width
                                                text: block.modelData.note
                                                color: ui.dim
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                visible: block.height > 46 && text !== ""
                                            }
                                        }
                                        MouseArea {
                                            id: blockMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: editor.openFor(block.modelData)
                                        }
                                    }
                                }

                                // Now line.
                                Rectangle {
                                    visible: dayCol.today
                                    y: (backend.nowSec - dayCol.dayStart) / 3600 * page.hourHeight
                                    width: parent.width
                                    height: 2
                                    color: ui.red
                                    Rectangle { x: -4; y: -3; width: 8; height: 8; color: ui.red; radius: Math.min(4, ui.radius) }
                                }
                            }
                        }
                    }
                }
            }

            // Month heatmap ----------------------------------------------
            ColumnLayout {
                id: monthView
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: page.view === "month"
                spacing: 6
                readonly property int lead: (page.rangeStart.getDay() + 6) % 7
                readonly property int count: Math.round((page.toSec - page.fromSec) / 86400)
                readonly property var perDay: { backend.revision; return backend.dayTotals(page.fromSec, count) }

                GridLayout {
                    id: month
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7
                    columnSpacing: 4
                    rowSpacing: 4
                    readonly property real goal: Math.max(1, backend.dailyGoalMin * 60)
                    Repeater {
                        model: 7
                        delegate: Text {
                            required property int index
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Qt.locale().dayName((index + 1) % 7, Locale.ShortFormat)
                            color: ui.dim
                            font.pixelSize: 11
                        }
                    }
                    Repeater {
                        model: monthView.lead + monthView.count
                        delegate: Rectangle {
                            id: cell
                            required property int index
                            readonly property int dayIndex: index - monthView.lead
                            readonly property bool real: dayIndex >= 0
                            readonly property date day: page.addDays(page.rangeStart, Math.max(0, dayIndex))
                            readonly property int sec: real ? monthView.perDay[dayIndex] || 0 : 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 40
                            radius: ui.small
                            visible: true
                            opacity: real ? 1 : 0
                            color: sec > 0 ? Qt.alpha(ui.accent, 0.15 + 0.7 * Math.min(1, sec / month.goal)) : ui.deep
                            border.width: real && page.sameDay(day, new Date()) ? 2 : 1
                            border.color: real && page.sameDay(day, new Date()) ? ui.accent : ui.line
                            Text { x: 6; y: 4; text: cell.real ? cell.day.getDate() : ""; color: ui.bright; font.pixelSize: 11 }
                            Text {
                                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 6
                                text: cell.sec > 0 ? win.hm(cell.sec) : ""
                                color: ui.bright
                                font.pixelSize: 11
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: cell.real
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { page.anchor = cell.day; page.view = "day" }
                            }
                        }
                    }
                }
            }

            // Summary ----------------------------------------------------
            ColumnLayout {
                Layout.preferredWidth: 210
                Layout.fillHeight: true
                visible: page.width > 820
                spacing: 6
                Text {
                    text: page.view === "day" ? qsTr("This day") : page.view === "week" ? qsTr("This week") : qsTr("This month")
                    color: ui.dim
                }
                Text { text: win.hm(page.totals.total); color: ui.bright; font.bold: true; font.pixelSize: 26 }
                Text { text: qsTr("%n session(s)", "", page.totals.count); color: ui.dim; font.pixelSize: 11 }
                Rectangle {
                    id: summaryBar
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    height: 8
                    color: ui.panel
                    Row {
                        spacing: 2
                        Repeater {
                            model: page.totals.list
                            delegate: Rectangle {
                                required property var modelData
                                height: 8
                                width: Math.max(2, (summaryBar.width - 2 * page.totals.list.length) * modelData.sec / Math.max(1, page.totals.total))
                                color: win.projectColor(modelData.color)
                            }
                        }
                    }
                }
                Repeater {
                    model: page.totals.list
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        Swatch { colorIndex: modelData.color }
                        Text { text: modelData.name; color: ui.text; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: win.hm(modelData.sec); color: ui.bright }
                    }
                }
                Item { Layout.fillHeight: true }
                Text {
                    Layout.fillWidth: true
                    visible: page.view !== "month"
                    text: qsTr("Double-click empty time to add a block.")
                    color: ui.dim
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    SessionEditor { id: editor }
}
