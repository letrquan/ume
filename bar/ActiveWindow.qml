import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

// Icon and title of the focused window, after a divider. Slides away when
// nothing is focused or there is no room.
//
// Its room (maxWidth, from the bar) changes when something next to it
// slides in or out (a stat's hover text, the middle island growing). The
// title follows that room in the same frame, no animation of its own, so
// the two together keep the island's edge where it is instead of the
// island overshooting and snapping back. A title longer than its room fades
// out at the cut (FadeEdge) instead of ending in "…", so nothing in it
// changes while the room moves.
Item {
    id: root

    // Widest it may get; the bar passes in the room left before the clock.
    property real maxWidth: Style.titleMaxWidth

    readonly property var toplevel: ToplevelManager.activeToplevel
    readonly property string appId: toplevel?.appId ?? ""
    // A terminal's spinner in front of the title is left out, so its ticking
    // doesn't draw the bar again: Claude Code's ◐ ◑ (✳ when idle), the
    // · ✢ ✳ ✶ ✻ ✽ kind and braille ones. Only when a space and more text
    // follow: "·Foo", "✻" and "· " stay as they are. (The switcher and the
    // overview show the whole title.)
    readonly property string title: (toplevel?.title ?? "").replace(/^[·✢✳✶✻✽◐-◓⠀-⣿]+\s+(?=\S)/, "")
    // The app list loads a moment after start; reading its length makes this
    // look up again once it's there.
    readonly property var entry: DesktopEntries.applications.values.length >= 0 && appId !== ""
        ? DesktopEntries.heuristicLookup(appId) : null
    // An icon name from the theme, or a file path (Zen ships a .png).
    readonly property string iconName: entry?.icon ?? appId
    readonly property string iconSource: iconName.startsWith("/") ? "file://" + iconName
        : Quickshell.iconPath(iconName, "application-x-executable")

    readonly property bool shown: title !== "" && maxWidth > 80

    // Divider, icon, the gaps and the padding after the text.
    readonly property real chrome: 11 + 16 + 8 * 2 + 10
    readonly property real room: Math.min(Style.titleMaxWidth, maxWidth)
    // The width the title asks for, in 32 px steps: a title that keeps
    // changing a little (a terminal's spinner) doesn't make the island slide
    // (and every window of the shell draw again) each time. A new title
    // glides to its width; a new room doesn't (see above).
    property real wanted: Math.min(Math.ceil(label.implicitWidth / 32) * 32, Style.titleMaxWidth - chrome) + chrome
    Behavior on wanted {
        NumberAnimation { duration: Motion.reveal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle }
    }
    // Sliding in and out (a window focused, or none), like Reveal.
    property real reveal: shown ? 1 : 0
    Behavior on reveal {
        NumberAnimation { duration: Motion.reveal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle }
    }

    // The whole title in a tip, when it's cut at the room's edge.
    TipArea {
        tip: row.implicitWidth > root.width + 1 ? (root.entry?.name ?? root.appId) : ""
        tipDetail: tip !== "" ? root.title : ""
    }

    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: Math.max(0, Math.min(wanted, room)) * reveal
    implicitHeight: row.implicitHeight
    visible: width > 0.5
    clip: true

    // The text fades out where the room ends, before the padding (part of
    // `chrome`).
    FadeEdge {
        width: row.implicitWidth
        height: root.height
        visibleWidth: Math.max(0, root.width - 10)
        opacity: Math.max(0, Math.min(1, (root.reveal - 0.25) / 0.6))

        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Divider {}

            AppIcon {
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 16
                source: root.iconSource
                name: root.entry?.name ?? root.appId
            }

            StyledText {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                color: Colors.textOnSurfaceVariant
            }
        }
    }
}
