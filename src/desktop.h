#pragma once

#include <QString>

// Talks to Hyprland about Tomate's own window: bring it to the workspace you
// are looking at instead of sending you to it.
namespace Desktop {
// The Tomate window's address, or empty when none is open. With a pid, only
// that process's window counts.
QString windowAddress(qint64 pid = 0);
// Moves the window to the workspace in view (bringing it back if hidden) and
// focuses it. Returns false when there is no Hyprland to ask.
bool summon(const QString &address);
}
