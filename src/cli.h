#pragma once

#include <QStringList>

// Commands that need no window, for the bar, key binds, scripts and agents:
// tomate status --json, tomate toggle, tomate report --week, ...
namespace Cli {
// True when the arguments name a CLI command rather than opening the window.
bool handles(const QStringList &args);
// Runs it and returns the process exit code (0 or 1, errors on stderr).
int run(const QStringList &args);
}
