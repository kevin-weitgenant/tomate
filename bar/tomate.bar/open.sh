#!/bin/bash
# Right-click on the bar widget: bring the Tomate window to the workspace in
# view, opening it there if it isn't running.
T=$(command -v tomate || echo "$HOME/.local/bin/tomate")
exec "$T" show
