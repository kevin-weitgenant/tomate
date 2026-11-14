import QtQuick

// A project's colour square.
Rectangle {
    property int colorIndex: 0
    property int size: 10
    width: size
    height: size
    radius: Math.min(2, ui.radius)
    color: win.projectColor(colorIndex)
}
