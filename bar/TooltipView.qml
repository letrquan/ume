import QtQuick
import qs.common
import qs.services

// The bar's tip (common/Tooltips.qml): a small glass pill under the item
// the mouse is on, with what it is, its state in words and its keys.
//
//      ( ◉ 1 2 · · | title )   ( 09:41 Sun 18 Oct )   ( ᯤ 🔊 70% ▮38 )
//                                                       ╭──────────────────╮
//                                                       │ Home Wi-Fi   72% │
//                                                       ╰──────────────────╯
//
// mango blurs this layer, and its blur can't fade, so the glass never
// fades either: the tip unrolls downward from the island (its height grows
// from nothing) and rolls back up; only what's written on it fades. Going
// to the next item, the pill slides and resizes there while the words
// cross over.
Item {
    id: root

    // The item whose tip is shown. Changing it fades the words out, swaps
    // them, and fades the new ones in (the pill moves meanwhile).
    property var src: Tooltips.source
    Behavior on src {
        // The first tip just takes its words (nothing to cross over yet).
        enabled: root.t > 0.01
        SequentialAnimation {
            NumberAnimation { target: content; property: "opacity"; to: 0; duration: 70 }
            PropertyAction {}
            NumberAnimation { target: content; property: "opacity"; to: 1; duration: 140 }
        }
    }

    readonly property string title: src?.tip ?? ""
    readonly property string detail: src?.tipDetail ?? ""
    readonly property string keys: Shortcuts.keys(src?.tipShortcut ?? "")

    // Something else is where the tip would be, or grows out of the bar:
    // a panel, the volume OSD, a popup. The tip waits rolled up (and comes
    // back if the mouse is still there when it's gone).
    readonly property bool covered: IslandState.takenOver || IslandState.controlCovering
        || IslandState.sysmonCovering || OsdState.mapped || VolumeState.open || UpdatesState.open || Notifs.centerOpen
        || SessionState.open || OverviewState.open || SwitcherState.open || CheatSheetState.open

    // 0 = rolled up into the island, 1 = out.
    readonly property bool showing: Tooltips.shown && !covered && !BarPopupState.open    // (the battery / USB drive popups too)
    property real t: showing ? 1 : 0
    Behavior on t {
        NumberAnimation {
            duration: root.showing ? 220 : 160
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.showing ? Motion.gentle : Motion.emphasizedAccel
        }
    }

    readonly property real padX: 12
    readonly property real padY: 7
    readonly property real pillTop: Style.barBottom + Style.tooltipGap
    readonly property real fullWidth: Math.ceil(content.implicitWidth) + padX * 2
    readonly property real fullHeight: Math.ceil(content.implicitHeight) + padY * 2

    // Where the pill settles: centred under the item, kept on the screen.
    property real targetX: Math.max(Style.marginEnds, Math.min(width - Style.marginEnds - fullWidth,
                                                               Tooltips.anchorX - fullWidth / 2))
    Behavior on targetX {
        enabled: root.t > 0.01
        NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle }
    }
    property real pillWidth: fullWidth
    Behavior on pillWidth {
        enabled: root.t > 0.01
        NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle }
    }
    property real pillHeight: fullHeight
    Behavior on pillHeight {
        enabled: root.t > 0.01
        NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle }
    }

    // A new tip asks mango for the keys again if they're old.
    Connections {
        target: Tooltips
        function onShownChanged() {
            if (Tooltips.shown)
                Shortcuts.refresh();
        }
    }

    Glass {
        id: pill

        // Unrolling: full width a little sooner than full height.
        readonly property real w: root.pillWidth * (0.7 + 0.3 * Math.min(1, root.t * 1.4))
        x: Math.round(root.targetX + (root.pillWidth - w) / 2)
        y: root.pillTop
        width: w
        height: root.pillHeight * root.t
        visible: height > 0.5
        radius: Math.min(height / 2, 14)
        color: Style.alpha(Colors.surfaceContainer, Style.tooltipOpacity)
        clip: true

        Column {
            id: content

            x: root.padX
            // Pinned to the pill's bottom while it unrolls, so the words
            // come down with it instead of being uncovered in place.
            y: pill.height - root.pillHeight + root.padY
            spacing: 2
            opacity: 1

            Row {
                spacing: 10

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: root.title
                    role: "label"
                    color: Colors.textOnSurface
                }
                // The keys, like the cheat sheet's: a small key cap.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.keys !== ""
                    width: keysText.implicitWidth + 10
                    height: keysText.implicitHeight + 4
                    radius: 5
                    color: "transparent"
                    border.width: 1
                    border.color: Style.alpha(Colors.textOnSurface, 0.25)

                    StyledText {
                        id: keysText
                        anchors.centerIn: parent
                        text: root.keys
                        role: "micro"
                        color: Colors.textOnSurfaceVariant
                    }
                }
            }
            // One line each, cut if long (a workspace's window titles).
            Repeater {
                model: root.detail === "" ? [] : root.detail.split("\n").slice(0, 8)

                StyledText {
                    required property string modelData
                    width: Math.min(implicitWidth, 320)
                    text: modelData
                    role: "caption"
                    color: Colors.textOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }
    }
}
