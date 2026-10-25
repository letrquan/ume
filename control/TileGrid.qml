import QtQuick
import qs.common
import qs.services

// The control center's tiles, two to a row, in Style.controlTiles' order
// (control/ControlTiles.qml has every tile). Under them, Edit:
//  - every listed tile shows (ones that can't right now are faded), each
//    with a − to take it away; drag one to move it (mouse or finger: press
//    and move); its clicks do nothing while editing;
//  - "Add tiles": the ones not shown, a tap adds one at the end;
//  - Done (or Esc) goes back. Every change is saved at once.
// Settings → Control center does the same with ↑ ↓.
Column {
    id: root

    spacing: 10

    readonly property bool editing: ControlState.editing
    readonly property real gap: 8
    readonly property real tileWidth: (width - gap) / 2
    readonly property real tileHeight: Style.ccTileHeight

    // While a tile is dragged: the order shown (saved when it's let go).
    property var dragOrder: null
    readonly property var order: dragOrder ?? ControlTiles.chosen

    function availableNow(id) {
        const s = ControlTiles.spec(id);
        return !s || typeof s.available !== "function" || s.available();
    }
    // In their places: every listed tile while editing, else the ones that
    // can show now.
    readonly property var shown: editing ? order : order.filter(id => availableNow(id))
    readonly property int rows: Math.ceil(shown.length / 2)

    // Leaving the control center (or Esc) ends a drag too.
    onEditingChanged: if (!editing) dragOrder = null

    Item {
        id: grid
        width: parent.width
        height: Math.max(0, root.rows * (root.tileHeight + root.gap) - root.gap)

        Behavior on height {
            enabled: root.editing
            NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
        }

        // One per tile there is (not per tile shown), so moving or adding
        // one never makes the others again.
        Repeater {
            model: ControlTiles.specs

            Item {
                id: cell

                required property var modelData
                readonly property string tileId: modelData.tileId
                readonly property bool listed: root.order.includes(tileId)
                readonly property int slot: root.shown.indexOf(tileId)
                // (Only asked for listed tiles: what it reads starts nothing for the others.)
                readonly property bool ready: listed && root.availableNow(tileId)
                property bool dragging: false
                property real dragX: 0
                property real dragY: 0

                width: root.tileWidth
                height: root.tileHeight
                visible: slot >= 0
                x: dragging ? dragX : (slot % 2) * (root.tileWidth + root.gap)
                y: dragging ? dragY : Math.floor(slot / 2) * (root.tileHeight + root.gap)
                z: dragging ? 10 : 0

                Behavior on x {
                    enabled: root.editing && !cell.dragging
                    NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                }
                Behavior on y {
                    enabled: root.editing && !cell.dragging
                    NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                }

                Loader {
                    id: tile
                    anchors.fill: parent
                    // Made while listed, like the old fixed tiles (the phone
                    // and Tailscale ones start their checks this way).
                    active: cell.listed
                    sourceComponent: cell.modelData.tile
                    opacity: root.editing && !cell.ready ? 0.45 : 1
                    scale: cell.dragging ? 1.04 : root.editing ? 0.96 : 1

                    Behavior on scale {
                        NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                    }
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                // Editing: the tile's own clicks stop here; press and move
                // drags it.
                MouseArea {
                    id: mover
                    anchors.fill: parent
                    enabled: root.editing
                    visible: enabled
                    preventStealing: true
                    cursorShape: cell.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    property point grab: Qt.point(0, 0)
                    property point start: Qt.point(0, 0)

                    onPressed: mouse => {
                        start = mapToItem(grid, mouse.x, mouse.y);
                        grab = Qt.point(mouse.x, mouse.y);
                    }
                    onPositionChanged: mouse => {
                        const p = mapToItem(grid, mouse.x, mouse.y);
                        if (!cell.dragging) {
                            if (Math.abs(p.x - start.x) + Math.abs(p.y - start.y) < 8)
                                return;
                            root.dragOrder = root.order.slice();
                            cell.dragX = cell.x;
                            cell.dragY = cell.y;
                            cell.dragging = true;
                        }
                        cell.dragX = Math.max(-8, Math.min(grid.width - cell.width + 8, p.x - grab.x));
                        cell.dragY = Math.max(-8, Math.min(grid.height - cell.height + 8, p.y - grab.y));
                        root.dragTo(cell.tileId, cell.dragX + cell.width / 2, cell.dragY + cell.height / 2);
                    }
                    onReleased: root.drop(cell)
                    onCanceled: root.drop(cell)
                }

                // − : off the control center (into the tray).
                MouseArea {
                    id: minus
                    x: -8
                    y: -8
                    width: 30
                    height: 30
                    visible: root.editing && !cell.dragging
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ControlTiles.remove(cell.tileId)

                    Rectangle {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        radius: 10
                        color: Colors.surfaceContainerHighest
                        border.width: 1
                        border.color: Style.alpha(Colors.textOnSurface, 0.15)
                        scale: minus.pressed ? 0.85 : 1
                        Behavior on scale { NumberAnimation { duration: Motion.fast } }

                        Icon {
                            anchors.centerIn: parent
                            name: "remove"
                            size: 16
                            color: Colors.textOnSurface
                        }
                    }
                }
            }
        }
    }

    // Moving the dragged tile over another's place takes that place.
    function dragTo(id, cx, cy) {
        const list = dragOrder;
        if (!list)
            return;
        const col = cx < width / 2 ? 0 : 1;
        const row = Math.max(0, Math.min(rows - 1, Math.floor(cy / (tileHeight + gap))));
        const to = Math.min(list.length - 1, row * 2 + col);
        const from = list.indexOf(id);
        if (from < 0 || from === to)
            return;
        const next = list.slice();
        next.splice(from, 1);
        next.splice(to, 0, id);
        dragOrder = next;
    }
    function drop(cell) {
        if (!cell.dragging)
            return;
        const list = dragOrder;
        cell.dragging = false;
        if (list && JSON.stringify(list) !== JSON.stringify(ControlTiles.chosen))
            ControlTiles.save(list);
        dragOrder = null;
    }

    // Edit / Done.
    Item {
        width: parent.width
        height: 28

        Clickable {
            anchors.right: parent.right
            implicitHeight: 28
            padding: 10
            onClicked: ControlState.editing = !ControlState.editing

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.editing ? "check" : "edit"
                size: 16
                color: root.editing ? Colors.primary : Colors.textOnSurfaceVariant
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.editing ? "Done" : "Edit"
                role: "caption"
                weight: root.editing ? 650 : 500
                color: root.editing ? Colors.primary : Colors.textOnSurfaceVariant
            }
        }

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            visible: root.editing
            text: "Drag to move · − to take away"
            role: "caption"
            color: Colors.textOnSurfaceVariant
        }
    }

    // The tray: tiles not shown (their names only; nothing of theirs runs).
    Column {
        width: parent.width
        spacing: 8
        visible: root.editing

        StyledText {
            x: 6
            text: ControlTiles.hidden.length > 0 ? "Add tiles" : "Every tile is shown"
            role: "caption"
            weight: 650
            color: Colors.textOnSurfaceVariant
        }

        Flow {
            width: parent.width
            spacing: 6

            Repeater {
                model: root.editing ? ControlTiles.hidden : []

                MouseArea {
                    id: chip

                    required property string modelData
                    readonly property var info: ControlTiles.spec(modelData)

                    width: chipRow.implicitWidth + 24
                    height: 34
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ControlTiles.add(modelData)

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Style.alpha(Colors.textOnSurface, 0.08)

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: Colors.textOnSurface
                            opacity: chip.pressed ? Style.pressTint : chip.containsMouse ? Style.hoverTint : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        }
                    }
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "add"
                            size: 16
                            color: Colors.primary
                        }
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: chip.info?.icon ?? "help"
                            size: 16
                            fill: 0
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.info?.label ?? chip.modelData
                            role: "label"
                        }
                    }
                }
            }
        }
    }
}
