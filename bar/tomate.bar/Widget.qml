import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Tomate in the bar: a small ring that empties as the block runs, the time
// left, and the project. It reads `tomate status --json` once a second; the
// timer itself lives in Tomate's database, so the bar and the window always
// agree, and the bar's tick also delivers end-of-block notifications when the
// window is closed.
BarWidget {
  id: root
  moduleName: "tomate.bar"

  property var status: null
  property bool available: false
  property var palette: ({})

  readonly property string phase: !status ? "" : status.idle ? "idle" : status.waiting ? "ready" : status.paused ? "paused" : status.phase
  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color stateColor: phase === "focus" ? accent
    : phase === "short" ? (palette.green || accent)
    : phase === "long" ? (palette.magenta || accent)
    : phase === "ready" ? (palette.yellow || accent)
    : phase === "paused" ? Qt.darker(foreground, 1.55)
    : foreground
  readonly property real fraction: status && status.length > 0 && !status.waiting ? Math.max(0, Math.min(1, status.remaining / status.length)) : 1
  readonly property int maxProject: Math.max(0, Number(setting("maxProjectLength", 18)))

  // Resolved once by the shell: the installed binary on PATH, or the per-user
  // install in ~/.local/bin, whichever exists.
  readonly property string tomateCommand: 'T=$(command -v tomate || echo "$HOME/.local/bin/tomate"); '

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function clock(sec) {
    sec = Math.max(0, Math.round(sec))
    var h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60
    var mm = (m < 10 ? "0" : "") + m, ss = (s < 10 ? "0" : "") + s
    return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss
  }
  function hm(sec) {
    var h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60)
    return h > 0 ? h + "h " + (m < 10 ? "0" : "") + m + "m" : m + "m"
  }
  function shorten(name) {
    name = String(name || "")
    if (maxProject === 0) return ""
    return name.length > maxProject ? name.slice(0, maxProject - 1) + "…" : name
  }
  // Project names and notes are the user's own text; the shared tooltip may
  // render markup, so neutralize it before it gets there.
  function plain(value) {
    return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
  function phaseName(p) { return strings.t(p === "short" ? "short" : p === "long" ? "long" : "focus") }

  readonly property string label: {
    if (!status || phase === "idle" || vertical) return ""
    if (phase === "ready") return strings.t("ready").arg(phaseName(status.phase))
    var time = clock(status.remaining)
    if (status.phase !== "focus") return time
    var project = shorten(status.project)
    return project ? time + " · " + project : time
  }

  readonly property string tooltip: {
    if (!status) return ""
    var s = status, lines = []
    var project = plain(s.project)
    var goal = s.goal > 0 ? strings.t("today").arg(hm(s.today)).arg(hm(s.goal)) : strings.t("todayNoGoal").arg(hm(s.today))
    if (phase === "idle") {
      lines.push("Tomate · " + project, goal, strings.t("hintIdle"))
    } else if (phase === "ready") {
      lines.push(strings.t("ready").arg(phaseName(s.phase)) + " · " + project,
                 strings.t("round").arg(s.round).arg(s.every), strings.t("hintReady"))
    } else if (phase === "paused") {
      lines.push(strings.t("paused") + " · " + project, strings.t("pausedNote"), strings.t("hintPaused"))
    } else {
      lines.push(phaseName(s.phase) + (s.phase === "focus" ? " · " + project : ""),
                 strings.t("round").arg(s.round).arg(s.every) + (s.ends ? " · " + strings.t("ends").arg(s.ends) : ""))
      if (s.phase === "focus" && s.note) lines.push("“" + plain(s.note) + "”")
      lines.push(goal, strings.t("hintRunning"))
    }
    return lines.join("\n")
  }

  function read(text) {
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed.remaining === "number") {
        root.status = parsed
        root.available = true
        return
      }
    } catch (e) {}
    root.available = false
  }
  function refresh() { if (!statusProc.running) statusProc.running = true }
  function run(args) {
    Quickshell.execDetached(["sh", "-c", root.tomateCommand + args])
    soon.restart()
  }
  function press(button) {
    if (button === Qt.RightButton)
      run('exec omarchy-launch-or-focus tomate "uwsm-app -- $T"')
    else if (button === Qt.LeftButton)
      run('exec "$T" toggle >/dev/null')
  }

  // Theme colours beyond the accent: green for short breaks, magenta for long
  // ones, yellow for "ready". Re-read when the theme changes.
  FileView {
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var out = {}, re = /^\s*([a-z_]+)\s*=\s*["'](#[0-9a-fA-F]{6})["']/gm, m
      var t = text()
      while ((m = re.exec(t)) !== null) out[m[1]] = m[2]
      root.palette = out
    }
  }

  Process {
    id: statusProc
    command: ["sh", "-c", root.tomateCommand + 'exec "$T" status --json']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.read(text)
    }
    onExited: function(exitCode) { if (exitCode !== 0) root.available = false }
  }
  Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  // After a click, show the new state without waiting for the next second.
  Timer { id: soon; interval: 150; onTriggered: root.refresh() }

  visible: available
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label || "◔"
    labelVisible: false
    hasVisualContent: root.available
    fixedWidth: root.vertical ? -1 : content.width + Style.spaceReal(8.5) * 2
    tooltipText: root.tooltip
    onPressed: function(b) { root.press(b) }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(6)
      scale: button.pressScale

      Canvas {
        id: ring
        readonly property real size: Math.max(10, Style.bar.iconSize + 2)
        width: size
        height: size
        anchors.verticalCenter: parent.verticalCenter
        property real fraction: root.fraction
        property color tint: root.stateColor
        property color track: Qt.alpha(root.foreground, 0.22)
        onFractionChanged: requestPaint()
        onTintChanged: requestPaint()
        onTrackChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var c = width / 2, r = c - 1.6
          ctx.lineWidth = 2.4
          ctx.strokeStyle = track
          ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.stroke()
          if (fraction > 0) {
            ctx.strokeStyle = tint
            ctx.beginPath()
            ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * fraction)
            ctx.stroke()
          }
          // Paused: two bars in the middle; ready: a small play triangle.
          if (root.phase === "paused" || root.phase === "ready") {
            ctx.fillStyle = tint
            if (root.phase === "paused") {
              ctx.fillRect(c - 2.4, c - 2.6, 1.6, 5.2)
              ctx.fillRect(c + 0.8, c - 2.6, 1.6, 5.2)
            } else {
              ctx.beginPath(); ctx.moveTo(c - 1.8, c - 2.8); ctx.lineTo(c + 2.8, c); ctx.lineTo(c - 1.8, c + 2.8); ctx.closePath(); ctx.fill()
            }
          }
        }
        Connections { target: root; function onPhaseChanged() { ring.requestPaint() } }
      }

      Text {
        visible: text !== ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.label
        color: root.stateColor
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }
    }
  }

  // "Ready" waits for you: flash three times so it gets noticed even if the
  // notification was missed. Kept short and skipped when animations are off.
  SequentialAnimation {
    id: flash
    loops: 3
    NumberAnimation { target: content; property: "opacity"; to: 0.25; duration: Style.duration(260); easing.type: Easing.OutCubic }
    NumberAnimation { target: content; property: "opacity"; to: 1; duration: Style.duration(260); easing.type: Easing.OutCubic }
  }
  onPhaseChanged: {
    if (phase === "ready") flash.restart()
    else { flash.stop(); content.opacity = 1 }
  }
}
