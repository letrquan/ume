import QtQuick
import qs.common
import qs.services

// One dock slot: an app icon that grows when the pointer is near (the
// size comes from DockView), a dot per open window (up to 3; the focused
// window's turns into a wide accent pill), and one bounce when it starts.
// A red badge with the app's unread count (or a dot when it asks for
// attention) and a thin progress bar, from services/Badges.qml.
// "|" is the thin divider between pinned and running-only apps.
Item {
    id: root

    required property string modelData    // DockState key, or "|"
    required property int index
    required property var view            // DockView: sizes and the menu

    readonly property bool divider: modelData === "|"
    readonly property var item: divider ? null : DockState.item(modelData)
    readonly property int windows: item?.toplevels.length ?? 0
    readonly property bool focused: item?.toplevels.some(t => t.activated) ?? false
    // Which of the (at most 3) dots is the focused window's: past the third,
    // the last dot stands for it.
    readonly property int focusedDot: {
        const i = item?.toplevels.findIndex(t => t.activated) ?? -1;
        return i < 0 ? -1 : Math.min(i, 2);
    }
    readonly property real size: divider ? 0 : Style.dockIconSize * view.scaleFor(index)
    readonly property bool hovered: pointer.containsMouse

    width: divider ? view.dividerWidth : size
    height: view.rowHeight

    // Start-up feedback: one hop.
    function bounce() {
        hop.restart();
    }

    // ---- Divider ---------------------------------------------------------------------
    Rectangle {
        visible: root.divider && !Style.dockDark
        anchors.bottom: parent.bottom
        anchors.bottomMargin: (Style.dockIconSize - height) / 2
        width: 1
        height: Style.dockIconSize * 0.7
        color: Style.alpha(Colors.textOnSurface, 0.18)
    }

    // ---- Icon ------------------------------------------------------------------------
    // Decoded once at the biggest size and scaled, so growing on hover never
    // re-renders the icon (the tile under it is a shader: free to resize).
    AppIcon {
        id: icon
        visible: !root.divider
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: root.size
        height: root.size
        source: root.divider ? "" : DockState.iconFor(root.item)
        name: root.item?.entry?.name ?? root.item?.appId ?? ""
        sourceSize: Qt.size(Style.dockIconSize * Style.dockMagnify * 2, Style.dockIconSize * Style.dockMagnify * 2)
        mipmap: true
        transform: Translate {
            id: lift
        }
        scale: pointer.pressed ? 0.9 : 1

        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }
    }

    SequentialAnimation {
        id: hop
        NumberAnimation { target: lift; property: "y"; to: -Style.dockIconSize * 0.35; duration: 220; easing.type: Easing.OutQuad }
        NumberAnimation { target: lift; property: "y"; to: 0; duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.slowSpatial }
    }

    // ---- Badge and progress (services/Badges.qml) ------------------------------------
    readonly property var badge: divider ? Badges.none : Badges.of(item)
    readonly property int count: badge.count
    readonly property bool urgent: badge.urgent
    readonly property real progress: badge.progress

    // Laid out once at the icon's resting size and scaled with it, so the
    // icon growing never re-lays out the number; it hops with the icon.
    Item {
        visible: !root.divider && Style.dockBadges
        anchors.horizontalCenter: icon.horizontalCenter
        anchors.bottom: icon.bottom
        width: Style.dockIconSize
        height: Style.dockIconSize
        transform: Translate { y: lift.y }

        Item {
            anchors.fill: parent
            scale: root.size / Style.dockIconSize * icon.scale
            transformOrigin: Item.Bottom

            // The count (99+ past that), or a dot when it only asks for
            // attention. A thin ring in the dock's color keeps it apart.
            Rectangle {
                id: pill
                readonly property bool shows: root.count > 0 || root.urgent
                readonly property bool dot: root.count === 0

                height: dot ? 12 : 18
                width: dot ? 12 : Math.max(18, number.implicitWidth + 10)
                radius: height / 2
                x: parent.width - width * (dot ? 0.85 : 0.7)
                y: -height * (dot ? 0.15 : 0.3)
                color: Colors.error
                border.width: 1.5
                border.color: Style.dockDark ? Colors.surfaceContainerLowest : Style.alpha(Colors.surfaceContainer, 0.9)
                visible: scale > 0.01
                scale: shows ? 1 : 0

                Behavior on scale {
                    NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                }

                StyledText {
                    id: number
                    anchors.centerIn: parent
                    visible: !pill.dot
                    text: root.count > 99 ? "99+" : String(root.count)
                    role: "micro"
                    weight: 750
                    font.features: ({ "tnum": 1 })
                    color: Colors.textOnError
                }
            }

            // Progress (a download, a copy…), along the bottom of the icon.
            Rectangle {
                visible: Style.dockBadgeProgress && root.progress >= 0
                x: Math.round(parent.width * 0.14)
                y: parent.height - 9
                width: parent.width - 2 * x
                height: 5
                radius: 2.5
                color: Style.alpha(Colors.surface, 0.75)
                border.width: 1
                border.color: Style.alpha(Colors.textOnSurface, 0.2)

                Rectangle {
                    x: 1
                    y: 1
                    height: parent.height - 2
                    width: Math.max(height, (parent.width - 2) * Math.max(0, root.progress))
                    radius: height / 2
                    color: Colors.primary
                    Behavior on width {
                        NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle }
                    }
                }
            }
        }
    }

    // ---- Window dots -----------------------------------------------------------------
    Row {
        visible: Style.dockRunningDots && !root.divider && root.windows > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 2
        spacing: 3

        Repeater {
            model: Math.min(3, root.windows)

            Rectangle {
                id: dot
                required property int index
                readonly property bool current: index === root.focusedDot

                width: current ? 14 : 4
                height: 4
                radius: 2
                color: current ? Colors.primary : Style.alpha(Colors.textOnSurface, 0.6)
                // A new window's dot pops in.
                scale: 0
                Component.onCompleted: scale = 1

                Behavior on width {
                    NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                }
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on scale {
                    NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                }
            }
        }
    }

    // ---- Clicks ----------------------------------------------------------------------
    MouseArea {
        id: pointer
        anchors.fill: icon
        enabled: !root.divider
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onContainsMouseChanged: root.view.setHovered(root, containsMouse)
        onClicked: mouse => {
            root.view.dismissPreview();
            if (mouse.button === Qt.RightButton) {
                root.view.menuRequested(root);
            } else if (mouse.button === Qt.MiddleButton) {
                DockState.launch(root.item);
                root.bounce();
            } else if (DockState.open(root.item)) {
                root.bounce();
            }
        }
    }
}
