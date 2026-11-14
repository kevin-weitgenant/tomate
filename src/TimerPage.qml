import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

// The screen you leave open: project, intention, the ring, presets, controls
// and today's total.
Item {
    id: page
    property bool editing: false

    function openEditor() {
        page.editing = true
        focusEdit.text = win.minutes(backend.cycle.focusMin)
        breakEdit.text = win.minutes(backend.cycle.shortMin)
        roundsEdit.text = String(backend.cycle.every)
        focusEdit.forceActiveFocus()
        focusEdit.selectAll()
    }
    function applyEditor() {
        const f = parseFloat(focusEdit.text.replace(",", ".")), b = parseFloat(breakEdit.text.replace(",", "."))
        const r = parseInt(roundsEdit.text)
        if (f > 0 && b > 0 && r > 0)
            backend.setCustomCycle(f, b, r)
        page.editing = false
    }
    function saveEditorAsPreset() {
        applyEditor()
        backend.saveCycleAsPreset(qsTr("Custom %1/%2").arg(win.minutes(backend.cycle.focusMin)).arg(win.minutes(backend.cycle.shortMin)))
    }

    Shortcut { sequence: "P"; context: Qt.ApplicationShortcut; enabled: !win.typing && !win.modal; onActivated: picker.open() }
    Shortcut { sequence: "E"; context: Qt.ApplicationShortcut; enabled: !win.typing && !win.modal; onActivated: { win.page = 0; page.openEditor() } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 10

        // Project ----------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Rectangle {
                id: projectButton
                implicitWidth: projectRow.implicitWidth + 24
                implicitHeight: 34
                radius: ui.small
                color: projectMouse.containsMouse ? ui.sel : ui.panel
                border.color: ui.line
                Row {
                    id: projectRow
                    anchors.centerIn: parent
                    spacing: 10
                    Swatch { anchors.verticalCenter: parent.verticalCenter; colorIndex: (win.project(backend.projectId) || {}).color || 0 }
                    Text { text: (win.project(backend.projectId) || {}).name || qsTr("No project"); color: ui.bright; font.bold: true }
                    Text { text: "▾  P"; color: ui.dim }
                }
                MouseArea { id: projectMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: picker.open() }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: backend.cycle.custom ? qsTr("Custom cycle") : backend.cycle.name
                color: ui.dim
            }
        }

        // Intention --------------------------------------------------------
        Field {
            id: intention
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(460, page.width - 48)
            Layout.topMargin: 8
            horizontalAlignment: TextInput.AlignHCenter
            placeholder: qsTr("What are you focusing on?")
            // No binding to backend.note: the backend ticks twice a second and
            // a binding would overwrite what is being typed. Instead the saved
            // note flows in only while the field isn't being edited.
            Component.onCompleted: text = backend.note
            onEditingFinished: save()
            onAccepted: intention.input.focus = false
            function save() {
                saveTimer.stop()
                if (text.trim() !== backend.note) backend.setNote(text)
            }
            // Save shortly after typing stops, so nothing is lost if the
            // window closes before Enter or a click elsewhere.
            Timer { id: saveTimer; interval: 800; onTriggered: intention.save() }
            Connections {
                target: intention.input
                function onTextEdited() { saveTimer.restart() }
            }
            Connections {
                target: backend
                function onTicked() {
                    if (!intention.input.activeFocus && !saveTimer.running && intention.text !== backend.note)
                        intention.text = backend.note
                }
            }
        }

        // Ring -------------------------------------------------------------
        Item {
            id: ringBox
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 240

            readonly property real size: Math.min(width, height, 340)
            readonly property color phaseColor: backend.paused ? ui.dim : win.phaseColor(backend.phase)

            Shape {
                id: ring
                width: ringBox.size
                height: ringBox.size
                anchors.centerIn: parent
                preferredRendererType: Shape.CurveRenderer
                property real progress: backend.progress
                Behavior on progress { NumberAnimation { duration: 480 } }

                ShapePath {
                    strokeColor: ui.panel
                    strokeWidth: 10
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    PathAngleArc {
                        centerX: ring.width / 2; centerY: ring.height / 2
                        radiusX: ring.width / 2 - 8; radiusY: ring.height / 2 - 8
                        startAngle: -90; sweepAngle: 360
                    }
                }
                ShapePath {
                    strokeColor: ringBox.phaseColor
                    strokeWidth: 10
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    PathAngleArc {
                        centerX: ring.width / 2; centerY: ring.height / 2
                        radiusX: ring.width / 2 - 8; radiusY: ring.height / 2 - 8
                        startAngle: -90
                        // The ring empties as time runs out, like Session.
                        sweepAngle: 360 * (1 - ring.progress)
                    }
                }
            }

            // Centre: the countdown.
            Column {
                anchors.centerIn: parent
                spacing: 4
                visible: !page.editing
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: backend.paused ? qsTr("PAUSED") : win.phaseName(backend.phase).toUpperCase()
                    color: ringBox.phaseColor
                    font.bold: true
                    font.letterSpacing: 3
                    font.pixelSize: 12
                }
                Text {
                    id: bigTime
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.clock(backend.remainingSec)
                    color: ui.bright
                    font.pixelSize: Math.max(36, ringBox.size * 0.2)
                    font.bold: true
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.openEditor()
                        hoverEnabled: true
                        ToolTip.visible: containsMouse
                        ToolTip.delay: 600
                        ToolTip.text: qsTr("Change the times for this cycle (E)")
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: ui.dim
                    font.pixelSize: 12
                    text: backend.idle ? qsTr("Space to start")
                        : backend.waiting ? qsTr("ready · Space to start")
                        : backend.paused ? qsTr("round %1 of %2 · Space to resume").arg(backend.round).arg(backend.every)
                        : qsTr("round %1 of %2 · ends %3").arg(backend.round).arg(backend.every).arg(win.timeOf(backend.endsAt))
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    topPadding: 4
                    Repeater {
                        model: Math.min(backend.every, 12)
                        delegate: Rectangle {
                            required property int index
                            width: 10; height: 10
                            radius: Math.min(2, ui.radius)
                            readonly property bool done: index + 1 < backend.round || (index + 1 === backend.round && backend.phase !== "focus")
                            readonly property bool current: index + 1 === backend.round && backend.phase === "focus" && !backend.waiting
                            color: done ? ui.accent : current ? Qt.alpha(ui.accent, 0.4) : "transparent"
                            border.color: ui.accent
                        }
                    }
                }
            }

            // Centre, while editing: custom times for this cycle only.
            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: page.editing
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("THIS CYCLE")
                    color: ui.dim
                    font.letterSpacing: 3
                    font.pixelSize: 11
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    Repeater {
                        model: [
                            { label: qsTr("focus"), suffix: "/" },
                            { label: qsTr("break"), suffix: "×" },
                            { label: qsTr("rounds"), suffix: "" }
                        ]
                        delegate: Row {
                            id: cell
                            required property var modelData
                            required property int index
                            spacing: 10
                            Column {
                                spacing: 2
                                Field {
                                    width: 64
                                    horizontalAlignment: TextInput.AlignHCenter
                                    font.pixelSize: 30
                                    font.bold: true
                                    validator: RegularExpressionValidator { regularExpression: cell.index === 2 ? /\d{0,2}/ : /\d{0,3}([.,]\d)?/ }
                                    Component.onCompleted: {
                                        if (cell.index === 0) page.focusEdit = input
                                        else if (cell.index === 1) page.breakEdit = input
                                        else page.roundsEdit = input
                                    }
                                    tabTarget: cell.index === 0 ? page.breakEdit : cell.index === 1 ? page.roundsEdit : page.focusEdit
                                    onAccepted: page.applyEditor()
                                    onEscaped: page.editing = false
                                    onStepped: delta => { input.text = win.minutes(Math.max(1, (parseFloat(input.text.replace(",", ".")) || 0) + delta)) }
                                }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: cell.modelData.label; color: ui.dim; font.pixelSize: 11 }
                            }
                            Text { text: cell.modelData.suffix; color: ui.dim; font.pixelSize: 26; visible: text !== ""; y: 6 }
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("minutes · Esc cancels")
                    color: ui.dim
                    font.pixelSize: 11
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Btn { text: qsTr("Apply"); kbd: "Enter"; primary: true; onClicked: page.applyEditor() }
                    Btn { text: qsTr("Save preset"); kbd: "Ctrl+S"; onClicked: page.saveEditorAsPreset() }
                }
                Shortcut { sequence: "Ctrl+S"; enabled: page.editing; onActivated: page.saveEditorAsPreset() }
            }
        }

        // Presets ----------------------------------------------------------
        Flow {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: page.width - 48
            spacing: 6
            Repeater {
                model: backend.presets
                delegate: Btn {
                    required property var modelData
                    implicitHeight: 28
                    text: modelData.name + " " + win.minutes(modelData.focusMin) + "/" + win.minutes(modelData.shortMin)
                    checked: !backend.cycle.custom && backend.cycle.presetId === modelData.id
                    onClicked: backend.usePreset(modelData.id)
                }
            }
            Btn {
                implicitHeight: 28
                visible: backend.cycle.custom
                checked: true
                text: qsTr("Custom %1/%2").arg(win.minutes(backend.cycle.focusMin)).arg(win.minutes(backend.cycle.shortMin))
                onClicked: page.openEditor()
            }
            Btn { implicitHeight: 28; visible: !backend.cycle.custom; text: qsTr("Custom…"); kbd: "E"; onClicked: page.openEditor() }
        }

        // Controls ---------------------------------------------------------
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            spacing: 8
            Btn {
                primary: true
                implicitWidth: 140
                text: backend.running ? qsTr("Pause") : backend.paused ? qsTr("Resume") : qsTr("Start")
                kbd: "Space"
                onClicked: backend.toggle()
            }
            Btn { text: qsTr("Skip"); kbd: "S"; onClicked: backend.skip() }
            Btn { text: qsTr("Stop"); kbd: "X"; enabledState: !backend.idle; onClicked: backend.stop() }
        }

        // Today ------------------------------------------------------------
        Rectangle { Layout.fillWidth: true; Layout.topMargin: 12; height: 1; color: ui.line }
        RowLayout {
            Layout.fillWidth: true
            Text { text: qsTr("Today"); color: ui.bright; font.bold: true }
            Text { text: win.hm(backend.todaySec); color: ui.text }
            Item { Layout.fillWidth: true }
            Text {
                visible: backend.dailyGoalMin > 0
                text: qsTr("goal %1").arg(win.hm(backend.dailyGoalMin * 60))
                color: backend.todaySec >= backend.dailyGoalMin * 60 ? ui.green : ui.dim
            }
        }
        Rectangle {
            id: todayBar
            Layout.fillWidth: true
            height: 8
            color: ui.panel
            radius: Math.min(2, ui.radius)
            readonly property real scale: Math.max(backend.dailyGoalMin * 60, backend.todaySec, 1)
            Row {
                height: parent.height
                spacing: 2
                Repeater {
                    model: backend.todayByProject
                    delegate: Rectangle {
                        required property var modelData
                        height: todayBar.height
                        width: Math.max(2, (todayBar.width - 2 * backend.todayByProject.length) * modelData.sec / todayBar.scale)
                        color: win.projectColor(modelData.color)
                    }
                }
            }
        }
    }

    // Handles for the three editor inputs, filled in by the Repeater.
    property Item focusEdit
    property Item breakEdit
    property Item roundsEdit

    ProjectPicker { id: picker }
}
