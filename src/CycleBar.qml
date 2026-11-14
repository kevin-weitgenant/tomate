import QtQuick

// One full cycle of a preset drawn to scale: focus, break, focus, …, long break.
Row {
    id: root
    property var preset
    spacing: 2
    readonly property var parts: {
        const out = []
        if (!preset) return out
        for (let i = 0; i < preset.every; i++) {
            out.push([preset.focusMin, ui.accent])
            out.push(i === preset.every - 1 ? [preset.longMin, ui.magenta] : [preset.shortMin, ui.green])
        }
        return out
    }
    readonly property real total: parts.reduce((a, p) => a + p[0], 0)
    Repeater {
        model: root.parts
        delegate: Rectangle {
            required property var modelData
            height: root.height
            width: Math.max(1, (root.width - root.spacing * (root.parts.length - 1)) * modelData[0] / Math.max(1, root.total))
            color: modelData[1]
        }
    }
}
