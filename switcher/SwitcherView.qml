import QtQuick
import Quickshell
import qs.common

// The Alt+Tab strip: a glass card in the middle of the screen with one
// icon per window (most recent first), the picked one in a soft accent
// pill that slides, its app name and window title underneath.
//
//      ╭──────────────────────────────────────────────╮
//      │  ▢   ▣   ▢   ▢   ▢                           │
//      │     Zen Browser · Custom shell UI setup      │
//      ╰──────────────────────────────────────────────╯
//
// Plain QtQuick, so it can be previewed outside the shell.
Item {
    id: root

    property var windows: []
    property int selected: 0
    property bool shown: false
    // Workspace number of a window (0 = unknown).
    property var tagOf: t => 0

    signal hoveredIndex(int index)
    signal picked(int index)

    readonly property real cell: Style.switcherCell
    readonly property int perRow: Math.max(1, Math.floor((width * 0.86 - 32) / cell))
    readonly property var current: windows[selected] ?? null

    // The app list loads a moment after start; the bindings below read this
    // so they look again once it's there.
    readonly property int appsLoaded: DesktopEntries.applications.values.length

    function entryFor(t) {
        return appsLoaded >= 0 && t?.appId ? (DesktopEntries.byId(t.appId) ?? DesktopEntries.heuristicLookup(t.appId)) : null;
    }
    // An icon for a window: its app's .desktop icon (a name or a file), or
    // the app id as an icon name.
    function iconFor(t) {
        const entry = entryFor(t);
        const icon = entry?.icon ?? t?.appId ?? "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }
    function appName(t) {
        const entry = entryFor(t);
        return entry?.name ?? t?.appId ?? "";
    }

    Item {
        id: card

        anchors.centerIn: parent
        width: Math.min(root.windows.length, root.perRow) * root.cell + 32
        height: strip.height + 76
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.94

        Behavior on opacity {
            NumberAnimation {
                duration: root.shown ? Motion.contentIn : Motion.contentOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.shown ? Motion.emphasizedDecel : Motion.emphasizedAccel
            }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }
        Behavior on width {
            NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
        }

        // mango doesn't blur this window (it can't fade its blur): the
        // frost is the shell's own, so it comes and goes with the card.
        WallpaperFrost {
            anchors.fill: parent
            at: Qt.point(card.x, card.y)
            radius: Style.switcherRadius
        }
        Glass {
            anchors.fill: parent
            radius: Style.switcherRadius
            color: Style.alpha(Colors.surfaceContainer, Style.switcherOpacity)
        }

        // Clicks on the card stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        GridView {
            id: strip

            x: 16
            y: 16
            width: Math.min(root.windows.length, root.perRow) * root.cell
            height: Math.ceil(root.windows.length / root.perRow) * root.cell
            cellWidth: root.cell
            cellHeight: root.cell
            interactive: false
            model: root.windows
            currentIndex: root.selected
            highlightFollowsCurrentItem: false

            // The pick: a soft accent pill that slides from icon to icon.
            highlight: Rectangle {
                x: strip.currentItem?.x ?? 0
                y: strip.currentItem?.y ?? 0
                width: root.cell
                height: root.cell
                radius: Style.inner(Style.switcherRadius, strip.x)
                color: Style.alpha(Colors.primary, 0.2)
                border.width: 1.5
                border.color: Style.alpha(Colors.primary, 0.7)

                Behavior on x {
                    NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }
                Behavior on y {
                    NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }
            }

            delegate: MouseArea {
                id: cellItem

                required property var modelData
                required property int index
                readonly property bool isSelected: index === root.selected
                readonly property int tag: root.tagOf(modelData)

                width: root.cell
                height: root.cell
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Only a real mouse move picks, so a still pointer doesn't
                // fight the keys.
                onPositionChanged: root.hoveredIndex(index)
                onClicked: root.picked(index)

                AppIcon {
                    anchors.centerIn: parent
                    implicitSize: Style.switcherIconSize
                    source: root.iconFor(cellItem.modelData)
                    name: root.appName(cellItem.modelData)
                    scale: cellItem.isSelected ? 1.06 : 0.92
                    opacity: cellItem.isSelected ? 1 : 0.8

                    Behavior on scale {
                        NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                    }
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                // Workspace number, small, in the corner.
                Rectangle {
                    visible: cellItem.tag > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    width: 18
                    height: 18
                    radius: 9
                    color: cellItem.isSelected ? Colors.primary : Style.alpha(Colors.surfaceContainerHighest, 0.95)

                    StyledText {
                        anchors.centerIn: parent
                        text: cellItem.tag
                        role: "micro"
                        color: cellItem.isSelected ? Colors.textOnPrimary : Colors.textOnSurfaceVariant
                    }
                }
            }
        }

        // The picked window: app name, then its title.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 22
            spacing: 8
            width: Math.min(implicitWidth, card.width - 40)

            StyledText {
                id: app
                anchors.verticalCenter: parent.verticalCenter
                text: root.appName(root.current)
                role: "title"
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== "" && text !== app.text
                width: Math.min(implicitWidth, card.width - 40 - app.implicitWidth - 8)
                text: root.current?.title ?? ""
                color: Colors.textOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }
}
