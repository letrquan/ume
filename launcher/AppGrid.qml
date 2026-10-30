import QtQuick
import qs.common
import qs.services

// The launcher's app grid, Launchpad style: every app as a big tile, A to
// Z, and chips across the top that show one group (Internet, Media, …;
// only the groups that have apps: Apps.gridGroupsShown). Flick or scroll
// it; a tap opens an app, a long press or a right click opens its menu.
// Keys (the launcher's search field passes them on): arrows move, Tab /
// Shift+Tab the next / previous group, Enter opens, the Menu key opens the
// menu. Typing searches instead (the launcher shows its results then).
//
//      [ All ] [ Internet ] [ Media ] [ Office ] [ Games ] …
//      ─────────────────────────────────────────────────────
//        (🦊)      (💬)      (🎵)      (📁)      (⌨)
//       Firefox   Discord   Spotify   Files    Terminal
Item {
    id: root

    property real iconSize: 60
    property real tileWidth: 116
    property real tileHeight: 112
    property string group: "all"
    property int selected: 0
    // The pointer doesn't move the selection (an app's menu is open).
    property bool frozen: false

    readonly property var groups: Apps.gridGroupsShown
    readonly property var shown: Apps.gridOf(group)
    readonly property int cols: Math.max(1, Math.floor((grid.width + 0.5) / tileWidth))
    readonly property real chipsHeight: 44
    // The tiles' grid view (for the tests and the menu).
    readonly property alias view: grid

    // It's made in the background (LauncherView): it fades in once it's there.
    property bool arrived: false
    Component.onCompleted: arrived = true
    opacity: arrived ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
    }

    signal chosen(var entry)
    // The tile (an Item, for where the menu goes) and its app's entry.
    signal menuRequested(var entry, Item tile)

    function move(by) {
        if (shown.length === 0)
            return;
        selected = Math.max(0, Math.min(shown.length - 1, selected + by));
        grid.positionViewAtIndex(selected, GridView.Contain);
    }
    function moveRows(by) {
        move(by * cols);
    }
    function moveGroup(by) {
        const i = Math.max(0, groups.findIndex(g => g.id === group));
        group = groups[(i + by + groups.length) % groups.length].id;
    }
    function openSelected() {
        const a = shown[selected];
        if (a)
            chosen(a.entry);
    }
    function menuFor(index) {
        const a = shown[index];
        if (!a)
            return;
        selected = index;
        grid.positionViewAtIndex(index, GridView.Contain);
        const tile = grid.itemAtIndex(index);
        if (tile)
            menuRequested(a.entry, tile);
    }

    onGroupChanged: {
        selected = 0;
        grid.positionViewAtBeginning();
    }
    // A group can empty out (its last app removed): back to All.
    onGroupsChanged: if (!groups.some(g => g.id === group)) group = "all"

    // ---- Groups --------------------------------------------------------------------
    ListView {
        id: chips
        x: 4
        y: 2
        width: parent.width - 8
        height: 34
        orientation: ListView.Horizontal
        spacing: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.groups

        delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property bool current: modelData.id === root.group

            width: chipRow.implicitWidth + 24
            height: 34
            radius: 17
            color: current ? Colors.secondaryContainer
                 : Style.alpha(Colors.textOnSurface, chipHover.hovered ? 0.12 : 0.06)
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: chip.modelData.icon
                    size: 16
                    color: chip.current ? Colors.textOnSecondaryContainer : Colors.textOnSurfaceVariant
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.modelData.label
                    role: "label"
                    color: chip.current ? Colors.textOnSecondaryContainer : Colors.textOnSurfaceVariant
                }
            }

            HoverHandler {
                id: chipHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: root.group = chip.modelData.id
            }
        }
    }

    Rectangle {
        x: 4
        y: root.chipsHeight
        width: parent.width - 8
        height: 1
        color: Style.alpha(Colors.textOnSurface, 0.1)
    }

    // ---- Tiles ---------------------------------------------------------------------
    GridView {
        id: grid

        y: root.chipsHeight + 5
        width: parent.width
        height: parent.height - y
        clip: true
        cellWidth: width / root.cols
        cellHeight: root.tileHeight
        // Light and quick under a finger: a rubber band at the ends while
        // dragging, a flick that glides.
        boundsBehavior: Flickable.DragOverBounds
        flickDeceleration: 2600
        maximumFlickVelocity: 5200
        pixelAligned: true
        model: root.shown
        currentIndex: root.selected
        highlightFollowsCurrentItem: false

        delegate: AppTile {
            iconSize: root.iconSize
            frozen: root.frozen
            selected: index === root.selected
            onHoveredTile: i => {
                if (!root.frozen)
                    root.selected = i;
            }
            onChosen: i => {
                root.selected = i;
                root.openSelected();
            }
            onMenuRequested: i => root.menuFor(i)
        }
    }

    // Nothing in this group (only while the app list loads).
    StyledText {
        anchors.centerIn: grid
        visible: root.shown.length === 0
        text: "No apps"
        role: "body"
        color: Colors.textOnSurfaceVariant
    }
}
