#!/bin/bash
# Shows the Tomate window: brings it back if minimized, focuses it if open
# elsewhere, launches it otherwise. Matches the window class exactly, so a
# browser tab or file with "tomate" in its title is never picked instead.

T=$(command -v tomate || echo "$HOME/.local/bin/tomate")

read -r ADDRESS WORKSPACE < <(hyprctl clients -j |
  jq -r 'first(.[] | select(.class == "tomate") | "\(.address) \(.workspace.name)") // empty')

if [[ -z ${ADDRESS:-} ]]; then
  exec setsid uwsm-app -- "$T"
fi

if [[ $WORKSPACE == special:* ]]; then
  # Minimized (or parked on a scratchpad): bring it to the workspace in view,
  # and drop the dock's "minimized from" note now that it's back.
  HERE=$(hyprctl activeworkspace -j | jq -r '.name')
  hyprctl dispatch "hl.dsp.window.move({ workspace = \"$HERE\", follow = true, window = \"address:$ADDRESS\" })" >/dev/null
  for tag in $(hyprctl clients -j | jq -r --arg a "$ADDRESS" '.[] | select(.address == $a) | (.tags // [])[] | select(startswith("omarchy-minimized-from-"))'); do
    hyprctl dispatch "hl.dsp.window.tag({ tag = \"-$tag\", window = \"address:$ADDRESS\" })" >/dev/null
  done
fi

hyprctl dispatch "hl.dsp.focus({ window = \"address:$ADDRESS\" })" >/dev/null
