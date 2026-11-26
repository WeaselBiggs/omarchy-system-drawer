import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One screen's drawer. The window stays mapped against the left edge and only
// slides its contents; while they are away the mask leaves just the trigger
// strip, so clicks fall through to the windows below.
PanelWindow {
  id: window

  property var drawer: null

  readonly property bool keyOpen: !!drawer && !!screen && drawer.keyScreen === screen.name
  property bool hoverOpen: false
  readonly property bool open: keyOpen || hoverOpen
  // The tile the keyboard or pointer is on, or -1.
  property int cursor: -1

  readonly property var actions: drawer ? drawer.actions : []
  readonly property int tileWidth: Style.space(84)
  readonly property int tileHeight: Style.space(62)
  readonly property int tileGap: Style.spacing.xxs
  readonly property int pad: Style.spacing.md
  readonly property int iconSize: Style.fontPx(2.0)
  readonly property int borderWidth: Style.normalBorderWidth
  // The body runs past the screen edge by this much, so its left corners and
  // left border are never seen and it reads as coming out of the edge.
  readonly property int overhang: Math.max(Style.cornerRadius, borderWidth)
  readonly property int bodyWidth: tileWidth + pad * 2 + borderWidth
  readonly property int bodyHeight: actions.length * tileHeight + Math.max(0, actions.length - 1) * tileGap + pad * 2 + borderWidth * 2
  // How long the pointer rests on the edge before the drawer comes out, so
  // a pointer thrown at the edge on its way elsewhere does not call it.
  readonly property int dwell: 120
  // The stretch of the edge that calls the drawer, centered on the screen.
  readonly property int triggerLength: Style.space(220)

  // 0 tucked away, 1 fully out. Going is quicker than coming.
  property real progress: open ? 1 : 0
  Behavior on progress {
    id: slide
    NumberAnimation {
      duration: Style.duration(slide.targetValue > 0 ? 200 : 130)
      easing.type: Easing.OutCubic
    }
  }

  onKeyOpenChanged: {
    if (keyOpen) {
      window.cursor = 0
      keys.forceActiveFocus()
      grabTimer.restart()
    } else {
      grabTimer.stop()
      window.grabArmed = false
      window.hoverOpen = false
    }
  }
  onOpenChanged: if (!open) window.cursor = -1

  function step(delta) {
    var count = window.actions.length
    if (count === 0) return
    window.cursor = window.cursor < 0 ? (delta > 0 ? 0 : count - 1) : (window.cursor + delta + count) % count
  }

  function activate(index) {
    if (window.drawer && index >= 0 && index < window.actions.length) window.drawer.run(window.actions[index])
  }

  visible: !remapGuard.remapping
  color: "transparent"
  WlrLayershell.namespace: "omarchy-system-drawer"
  // Under a fullscreen window the edge stays quiet, but the key still works.
  WlrLayershell.layer: window.keyOpen ? WlrLayer.Overlay : WlrLayer.Top
  WlrLayershell.keyboardFocus: window.keyOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  anchors.left: true
  implicitWidth: bodyWidth
  implicitHeight: bodyHeight

  mask: Region {
    item: window.open ? body : null

    Region { item: edgeTrigger }
  }

  ScreenMoveRemap {
    id: remapGuard
    window: window
  }

  // A click anywhere else dismisses a drawer opened by key. The grab starts a
  // beat after the drawer has the keyboard: started in the same moment, the
  // compositor clears it again while the surface is still changing layers.
  property bool grabArmed: false
  property int grabClears: 0

  Timer {
    id: grabTimer
    interval: 150
    onTriggered: window.grabArmed = window.keyOpen
  }

  HyprlandFocusGrab {
    active: window.grabArmed
    windows: [window]
    onCleared: {
      window.grabClears++
      if (window.grabArmed && window.drawer) window.drawer.close()
    }
  }

  Timer {
    id: dwellTimer
    interval: window.dwell
    onTriggered: if (edgeHover.hovered) window.hoverOpen = true
  }

  Timer {
    id: hideTimer
    interval: 250
    onTriggered: if (!bodyHover.hovered && !edgeHover.hovered) window.hoverOpen = false
  }

  Item {
    id: edgeTrigger

    x: 0
    y: Math.round((window.height - height) / 2)
    width: Math.max(1, Style.space(2))
    height: Math.min(window.height, window.triggerLength)

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) dwellTimer.restart()
        else hideTimer.restart()
      }
    }
  }

  Item {
    id: keys

    focus: true
    Keys.onPressed: function(event) {
      if (!window.keyOpen) return
      event.accepted = true
      switch (event.key) {
      case Qt.Key_Escape: window.drawer.close(); break
      case Qt.Key_Down: case Qt.Key_J: case Qt.Key_Tab: window.step(1); break
      case Qt.Key_Up: case Qt.Key_K: case Qt.Key_Backtab: window.step(-1); break
      case Qt.Key_Home: window.cursor = 0; break
      case Qt.Key_End: window.cursor = window.actions.length - 1; break
      case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: window.activate(window.cursor); break
      default: event.accepted = false
      }
    }
  }

  Rectangle {
    id: body

    x: -window.overhang - (1 - window.progress) * window.bodyWidth
    width: window.bodyWidth + window.overhang
    height: window.bodyHeight
    visible: window.progress > 0
    opacity: Math.min(1, window.progress * 2)
    color: Commons.Color.popups.background
    radius: Style.cornerRadius
    border.color: Commons.Color.popups.border
    border.width: window.borderWidth

    HoverHandler {
      id: bodyHover
      onHoveredChanged: if (!hovered) hideTimer.restart()
    }

    Column {
      x: window.overhang + window.pad
      y: window.borderWidth + window.pad
      spacing: window.tileGap

      Repeater {
        model: window.actions

        delegate: Item {
          id: tile

          required property int index
          required property var modelData
          readonly property bool hot: window.cursor === index

          width: window.tileWidth
          height: window.tileHeight
          opacity: window.progress
          // Tiles further down trail a little behind the panel on its way out.
          transform: Translate { x: -(1 - window.progress) * tile.index * Style.space(8) }

          Rectangle {
            anchors.fill: parent
            radius: Math.max(0, Style.cornerRadius - window.pad / 2)
            color: mouse.pressed ? Style.pressedFill : tile.hot ? Style.hoverFill : "transparent"
            border.color: tile.hot ? Style.hoverBorderColor : "transparent"
            border.width: tile.hot ? Style.hoverBorderWidth : 0
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.spacing.xs
            scale: mouse.pressed ? 0.96 : 1

            Behavior on scale { NumberAnimation { duration: Style.duration(100); easing.type: Easing.OutCubic } }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: tile.modelData.icon
              color: tile.hot ? Commons.Color.menu.selectedText : Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: window.iconSize
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              width: window.tileWidth - Style.spacing.sm
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: tile.modelData.label
              color: tile.hot ? Commons.Color.menu.selectedText : Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: window.cursor = tile.index
            onEntered: window.cursor = tile.index
            onExited: if (!window.keyOpen && window.cursor === tile.index) window.cursor = -1
            onClicked: window.activate(tile.index)
          }
        }
      }
    }
  }
}
