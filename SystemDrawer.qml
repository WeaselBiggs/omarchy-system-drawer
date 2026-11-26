import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

// The System menu as a drawer of icons on the left screen edge. It pulls out
// when the pointer rests on the middle of that edge, or on a key through
// `omarchy-shell dan.system-drawer toggle`.
Item {
  id: root

  property var shell: null
  property var manifest: null

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // The same conditions the System menu puts on its Suspend and Hibernate rows.
  property bool canSuspend: true
  property bool canHibernate: false

  // The screen the drawer was opened on by key, or "" when it was not. A
  // drawer opened by key takes the keyboard and stays until dismissed; one
  // opened by the pointer goes when the pointer leaves.
  property string keyScreen: ""

  function glyph(codePoint) {
    return String.fromCodePoint(codePoint)
  }

  // Nerd Font glyphs: a monitor, a padlock, the sleep Z's and a snowflake,
  // then the System menu's own for the last three.
  readonly property var actions: {
    var all = [
      { key: "screensaver", icon: glyph(0xF0379), command: "omarchy-launch-screensaver force", shown: true },
      { key: "lock", icon: glyph(0xF033E), command: "omarchy-system-lock", shown: true },
      { key: "suspend", icon: glyph(0xF04B2), command: "systemctl suspend", shown: root.canSuspend },
      { key: "hibernate", icon: glyph(0xF0717), command: "systemctl hibernate", shown: root.canHibernate },
      { key: "logout", icon: glyph(0xF0343), command: "omarchy-system logout", shown: true },
      { key: "reboot", icon: glyph(0xF0709), command: "omarchy-system reboot", shown: true },
      { key: "shutdown", icon: glyph(0xF0425), command: "omarchy-system shutdown", shown: true }
    ]
    var out = []
    for (var i = 0; i < all.length; i++) {
      if (!all[i].shown) continue
      out.push({ key: all[i].key, icon: all[i].icon, command: all[i].command, label: strings.t(all[i].key) })
    }
    return out
  }

  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    if (name) return name
    return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
  }

  function open() {
    root.readGuards()
    root.keyScreen = root.focusedScreenName()
  }

  function close() {
    root.keyScreen = ""
    var windows = drawers.instances
    for (var i = 0; i < windows.length; i++) windows[i].hoverOpen = false
  }

  function toggle() {
    if (root.keyScreen) root.close()
    else root.open()
  }

  function run(action) {
    if (!action) return
    root.close()
    Util.execDetached(action.command)
  }

  function readGuards() {
    if (!guardProc.running) guardProc.running = true
  }

  Process {
    id: guardProc
    command: ["bash", "-lc",
      "{ ! omarchy-toggle-enabled suspend-off && ! omarchy-sleep-disabled; } && echo suspend; "
      + "{ omarchy-hibernation-available && ! omarchy-sleep-disabled; } && echo hibernate; true"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.split("\n")
        root.canSuspend = lines.indexOf("suspend") >= 0
        root.canHibernate = lines.indexOf("hibernate") >= 0
      }
    }
  }

  Component.onCompleted: readGuards()

  ShellIpc {
    target: "dan.system-drawer"

    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function state(): string {
      var w = drawers.instances
      return JSON.stringify({ keyScreen: root.keyScreen, focused: root.focusedScreenName(), actions: root.actions.length,
        windows: w.map(function(x) { return { screen: x.screen ? x.screen.name : null, keyOpen: x.keyOpen, open: x.open, progress: x.progress, hover: x.hoverOpen, cursor: x.cursor, clears: x.grabClears } }) })
    }
  }

  Variants {
    id: drawers
    model: Quickshell.screens

    delegate: Component {
      DrawerWindow {
        required property var modelData

        screen: modelData
        drawer: root
      }
    }
  }
}
