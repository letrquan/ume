import QtQuick
import qs.common
import qs.dock
import qs.services

// An app's menu in the launcher: Open, the app's own actions ("New Private
// Window"…, from its desktop entry: Apps.actionsOf) and Pin to dock /
// Unpin. It comes out of a result row (→ at the end of the text, the Menu
// key, a right click or a long press) or a grid tile (a long press or a
// right click), inside the launcher's card:
//
//      ╭──────────────────────────╮
//      │ Firefox                  │
//      │ ▶  Open                  │
//      │ ◌  New Private Window    │
//      │ 📌 Pin to dock           │
//      ╰──────────────────────────╯
//
// ↑↓ move, Enter runs, ← or Esc closes it (the launcher's search field
// passes the keys on: key()); a click outside it closes it too.
Item {
    id: root

    property var entry: null
    property bool shown: false
    property int selected: 0
    // What it comes out of (the row or tile), in the parent's coordinates,
    // and the room it has (the card): below that, or above when there's no
    // room below; always inside.
    property rect from: Qt.rect(0, 0, 0, 0)
    property real roomWidth: parent?.width ?? 0
    property real roomHeight: parent?.height ?? 0
    // Lined up with the right end of what it comes out of (a row), or
    // centred on it (a tile).
    property bool alignRight: false

    // Something ran: the launcher closes.
    signal ran()

    readonly property bool pinned: entry ? DockState.isPinned(entry.id) : false
    readonly property var rows: {
        if (!entry)
            return [];
        const out = [{ id: "open", icon: "play_arrow", text: "Open" }];
        for (const a of Apps.actionsOf(entry))
            out.push({ id: "action", icon: a.icon, text: a.name, action: a.action });
        out.push({ id: "pin", icon: pinned ? "keep_off" : "keep", text: pinned ? "Unpin from dock" : "Pin to dock" });
        return out;
    }

    function openFor(e, rect, right) {
        entry = e;
        from = rect;
        alignRight = right ?? false;
        selected = 0;
        shown = true;
    }
    function close() {
        shown = false;
    }
    function move(by) {
        selected = Math.max(0, Math.min(rows.length - 1, selected + by));
    }
    function run(index) {
        const r = rows[index];
        if (!r || !entry)
            return;
        if (r.id === "pin") {
            // The launcher stays.
            DockState.togglePin(entry.id);
            shown = false;
            return;
        }
        if (r.id === "open")
            Apps.launch(entry);
        else
            Apps.launchAction(entry, r.action);
        shown = false;
        ran();
    }

    // A key while it's open: true when it took it. Anything else (typing)
    // closes it and goes on to the search field.
    function key(event) {
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Left:
        case Qt.Key_Menu:
            close();
            return true;
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            move(-1);
            return true;
        case Qt.Key_Down:
        case Qt.Key_Tab:
            move(1);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            run(selected);
            return true;
        }
        close();
        return false;
    }

    // Below what it comes out of, or above when it doesn't fit there.
    readonly property bool fitsBelow: from.y + from.height + 4 + height <= roomHeight - 8
    x: Math.round(Math.max(8, Math.min(roomWidth - width - 8,
        alignRight ? from.x + from.width - width : from.x + from.width / 2 - width / 2)))
    y: Math.round(fitsBelow ? from.y + from.height + 4 : Math.max(8, from.y - height - 4))
    width: Math.max(210, column.implicitWidth + 12)
    height: column.implicitHeight + 12
    visible: opacity > 0.01
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.94
    transformOrigin: fitsBelow ? Item.Top : Item.Bottom

    Behavior on opacity {
        NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
    }
    Behavior on scale {
        NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
    }

    // Clicks on it stay on it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Glass {
        anchors.fill: parent
        radius: 18
        color: Style.alpha(Colors.surfaceContainer, 0.94)
    }

    Column {
        id: column
        x: 6
        y: 6
        width: parent.width - 12

        StyledText {
            width: parent.width
            leftPadding: 10
            topPadding: 4
            bottomPadding: 6
            text: root.entry?.name ?? ""
            weight: 700
            elide: Text.ElideRight
        }

        Repeater {
            model: root.rows

            Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool current: index === root.selected

                width: column.width
                // Finger-sized in tablet mode.
                height: TabletMode.tablet ? 44 : 36

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: row.current ? Style.alpha(Colors.primary, 0.16) : Colors.textOnSurface
                    opacity: row.current ? 1 : area.pressed ? Style.pressTint : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: row.modelData.icon
                        size: 18
                        color: row.current ? Colors.primary : Colors.textOnSurfaceVariant
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.text
                        color: row.current ? Colors.primary : Colors.textOnSurface
                    }
                }

                // A MouseArea, not a TapHandler: a mouse click on a TapHandler
                // also reaches the TapHandlers under it (the grid's tiles).
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: root.selected = row.index
                    onClicked: root.run(row.index)
                }
            }
        }
    }
}
