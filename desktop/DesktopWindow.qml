import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

// The desktop of one screen: the clock and weather, and the widget cards
// (Style.desktopWidgets: music, system, calendar). Above the wallpaper,
// under every window. One window for all of it (each layer window costs a
// render thread and GL context), only as big as what it shows, placed by
// Style.desktopClockPosition.
// Clicks go through everywhere except the music card's buttons and the
// notes card (the mask). It never takes the keyboard (the notes card's
// typing happens in the notes panel).
// mango must not blur behind it (the text's shadow would get a frosted box):
// `layer_rule=no_blur:1,layer_name:^mine-desktop$` in shell-mine.conf.
PanelWindow {
    id: root

    required property ShellScreen modelData
    readonly property string position: Style.desktopClockPosition
    readonly property bool atBottom: position.startsWith("bottom")
    readonly property bool atRight: position.endsWith("right")
    readonly property real align: position.endsWith("left") ? 0 : atRight ? 1 : 0.5

    // Where the cards go: beside the clock, or stacked above it (bottom
    // corners) / under it (top corners, middle). "auto": beside at the top,
    // stacked at the bottom (beside would run into the dock) and in the middle.
    readonly property string side: Style.desktopWidgetsSide
    readonly property bool beside: side === "beside" || (side === "auto" && !atBottom && position !== "center")

    readonly property bool showClock: Style.desktopClock
    readonly property bool showCards: cards.anyShown

    screen: modelData
    // "center": no edge, so mango puts it in the middle (under the bar,
    // above the dock).
    anchors {
        top: position.startsWith("top")
        bottom: atBottom
        left: position.endsWith("left")
        right: atRight
    }
    margins {
        top: 24
        bottom: 24
        left: 32
        right: 32
    }
    // Keeps out of the bar's and dock's space, takes none itself.
    exclusiveZone: 0
    implicitWidth: Math.max(1, content.width)
    implicitHeight: Math.max(1, content.height)
    color: "transparent"

    WlrLayershell.namespace: "mine-desktop"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Only the music card's buttons and the notes card take clicks; the
    // rest is the desktop.
    mask: Region {
        item: cards.music
        Region {
            item: cards.notes
        }
    }

    // The way in (common/Intro.qml): last, after the bar and the dock, the
    // clock and cards fade in and settle from just below.
    property real introY: Intro.started && !Intro.enabled ? 0 : 12
    property real introOpacity: Intro.started && !Intro.enabled ? 1 : 0
    SequentialAnimation {
        id: comeIn
        PauseAnimation { duration: Style.dropInDelay * 5 }
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "introY"; to: 0; duration: Motion.slow
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
            }
            NumberAnimation {
                target: root; property: "introOpacity"; to: 1; duration: Motion.slow
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects
            }
        }
    }
    Component.onCompleted: if (Intro.started && introOpacity < 1) comeIn.start()
    Connections {
        target: Intro
        function onStartedChanged() {
            if (Intro.started && root.introOpacity < 1)
                comeIn.start();
        }
    }

    Item {
        id: content

        // The clock is a box with room for its text's shadow around it
        // (face.pad); the cards get the same kind of room for theirs (m).
        // Where the two boxes meet, that room is shared, not doubled.
        readonly property real m: 20
        readonly property real faceW: root.showClock ? face.implicitWidth : 0
        readonly property real faceH: root.showClock ? face.implicitHeight : 0
        readonly property real boxW: root.showCards ? cards.implicitWidth + 2 * m : 0
        readonly property real boxH: root.showCards ? cards.implicitHeight + 2 * m : 0
        readonly property real overlap: root.showClock && root.showCards ? Math.min(face.pad, m) : 0

        width: root.beside ? faceW + boxW - overlap : Math.max(faceW, boxW)
        height: root.beside ? Math.max(faceH, boxH) : faceH + boxH - overlap
        opacity: root.introOpacity
        transform: Translate { y: root.introY }

        ClockFace {
            id: face
            visible: root.showClock
            align: root.align
            x: root.beside ? (root.atRight ? content.width - width : 0) : (content.width - width) * root.align
            y: root.atBottom ? content.height - height : 0
        }

        // Beside: next to the clock, bottoms (or tops) lined up. Stacked:
        // above the clock at the bottom of the screen, under it elsewhere.
        DesktopWidgets {
            id: cards
            screenName: root.modelData.name
            readonly property real boxX: root.beside
                ? (root.atRight ? 0 : content.faceW - content.overlap)
                : (content.width - content.boxW) * root.align
            readonly property real boxY: root.beside
                ? (root.atBottom ? content.height - content.boxH : 0)
                : (root.atBottom ? 0 : content.faceH - content.overlap)
            x: boxX + content.m
            y: boxY + content.m
        }
    }
}
