#!/bin/bash
# Builds a short preview video (for a post) from docs/screenshots:
# title, captioned screens, the bar states, and the GitHub link, with
# crossfades and a slow push-in on each slide. Output: $1 (default
# ~/Videos/tomate-preview.mp4).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHOTS="$ROOT/docs/screenshots"
OUT="${1:-$HOME/Videos/tomate-preview.mp4}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

W=1440 H=900
BG="#13141c" PANEL="#1a1b26" ACCENT="#7aa2f7" FG="#c0caf5" DIM="#565f89" GREEN="#9ece6a"
BOLD=$(fc-match -f '%{file}' "JetBrainsMono Nerd Font:style=Bold")
REG=$(fc-match -f '%{file}' "JetBrainsMono Nerd Font")

# A screenshot as a window (2px accent border, like Hyprland) under a caption.
slide() { # name image caption
  magick "$2" -bordercolor "$ACCENT" -border 2 "$WORK/win.png"
  magick -size ${W}x${H} "xc:$BG" \
    "$WORK/win.png" -gravity center -geometry +0+42 -composite \
    -font "$BOLD" -pointsize 34 -fill "$ACCENT" -gravity north -annotate +0+44 "❯ $3" \
    "$WORK/$1.png"
}

# Title card.
magick -background none -density 600 "$ROOT/pkgbuild/tomate.svg" -resize 190x190 "$WORK/icon.png"
magick -size ${W}x${H} "xc:$BG" \
  "$WORK/icon.png" -gravity center -geometry +0-150 -composite \
  -font "$BOLD" -pointsize 112 -fill "$FG" -gravity center -annotate +0+40 "Tomate" \
  -font "$REG" -pointsize 34 -fill "$ACCENT" -annotate +0+140 "Pomodoro timer + time tracker for Omarchy" \
  -font "$REG" -pointsize 24 -fill "$DIM" -annotate +0+200 "projects · any timings · a calendar of your work" \
  "$WORK/00.png"

slide 01 "$SHOTS/timer.png"          "Pick a project. Press Space. Focus."
slide 02 "$SHOTS/custom-cycle.png"   "Any timings, even just for one cycle"
slide 03 "$SHOTS/calendar-week.png"  "See exactly when the work happened"
slide 04 "$SHOTS/calendar-month.png" "Your month at a glance"
slide 05 "$SHOTS/presets.png"        "Presets you control, breaks optional"

# The bar: the hover shot on top, then the other states, each labelled.
# The bar captures include a few pixels of wallpaper under the bar; paint
# them over with the background.
debar() { magick "$1" -fill "$BG" -draw "rectangle 0,27 9999,33" "$2"; }
row() { # state label
  debar "$SHOTS/bar/$1.png" "$WORK/clean-$1.png"
  magick "$WORK/clean-$1.png" -crop x26+0+0 +repage -scale 200% "$WORK/bar-$1.png"
  magick -size 1180x70 "xc:$BG" "$WORK/bar-$1.png" -gravity west -geometry +330+0 -composite \
    -font "$REG" -pointsize 26 -fill "$DIM" -gravity west -annotate +0+0 "$2" "$WORK/row-$1.png"
}
debar "$SHOTS/bar/hover.png" "$WORK/clean-hover.png"
magick "$WORK/clean-hover.png" -scale 200% -bordercolor "$ACCENT" -border 2 "$WORK/hover.png"
row short "short break"; row paused "paused"; row ready "waiting for you"; row idle "idle"
magick -size ${W}x${H} "xc:$BG" \
  -font "$BOLD" -pointsize 34 -fill "$ACCENT" -gravity north -annotate +0+44 "❯ Lives in your Omarchy bar. Click to pause." \
  "$WORK/hover.png" -gravity north -geometry +0+130 -composite \
  "$WORK/row-short.png" -geometry +0+510 -composite \
  "$WORK/row-paused.png" -geometry +0+590 -composite \
  "$WORK/row-ready.png" -geometry +0+670 -composite \
  "$WORK/row-idle.png" -geometry +0+750 -composite \
  "$WORK/06.png"

# End card.
magick -size ${W}x${H} "xc:$BG" \
  "$WORK/icon.png" -gravity center -geometry +0-170 -composite \
  -font "$BOLD" -pointsize 54 -fill "$FG" -gravity center -annotate +0+0 "github.com/kevin-weitgenant/tomate" \
  -font "$REG" -pointsize 30 -fill "$GREEN" -annotate +0+80 "free · open source · MIT" \
  -font "$REG" -pointsize 24 -fill "$DIM" -annotate +0+140 "C++ / Qt Quick · follows your Omarchy theme · local data only" \
  "$WORK/07.png"

# Seconds on screen per slide, and the crossfade length.
DUR=(2.6 2.8 2.6 2.8 2.4 2.6 3.6 3.4)
FADE=0.5
FPS=30

inputs=() filters="" prev="" offset=0
for i in "${!DUR[@]}"; do
  d=${DUR[$i]}
  inputs+=(-loop 1 -framerate $FPS -t "$d" -i "$WORK/0$i.png")
  # Slow push-in: render from a 2x source so the zoom doesn't shimmer.
  filters+="[$i:v]scale=$((W*2)):$((H*2)),zoompan=z='1+0.035*on/($d*$FPS)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=${W}x${H}:fps=$FPS,format=yuv420p,setsar=1[v$i];"
done
for i in "${!DUR[@]}"; do
  [[ $i -eq 0 ]] && { prev="v0"; offset=$(awk "BEGIN{print ${DUR[0]} - $FADE}"); continue; }
  filters+="[$prev][v$i]xfade=transition=fade:duration=$FADE:offset=$offset[x$i];"
  prev="x$i"
  offset=$(awk "BEGIN{print $offset + ${DUR[$i]} - $FADE}")
done

mkdir -p "$(dirname "$OUT")"
ffmpeg -v error -y "${inputs[@]}" -filter_complex "${filters%;}" -map "[$prev]" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart "$OUT"
echo "$OUT"
