import QtQuick
import qs.common
import qs.services

// What the right-click menu of a dock icon shows:
//   Firefox
//   ＋ New window
//   ◌ New private window      ← the app's own actions (its desktop entry's)
//   ─────
//   📌 Unpin from dock
//   ✕ Quit (2 windows)
// Plain QtQuick, so it can be previewed outside the shell.
Item {
    id: root

    property var item: null
    signal done()

    readonly property bool running: (item?.toplevels.length ?? 0) > 0
    readonly property bool pinned: item ? DockState.isPinned(item.key) : false
    // The app's own "new window" action: what "New window" runs.
    readonly property var newWindow: Apps.newWindowOf(item?.entry)
    readonly property var actions: {
        const out = [];
        if (item?.entry)
            out.push({ id: "new", icon: running ? "add" : "play_arrow", text: running ? "New window" : "Open" });
        // Its own actions ("New Private Window"…), but not its new-window
        // one a second time; a line under them.
        const own = Apps.actionsOf(item?.entry).filter(a => !Apps.isNewWindow(a));
        for (const a of own)
            out.push({ id: "action", icon: a.icon, text: a.name, action: a.action });
        if (own.length > 0)
            out.push({ id: "line", icon: "", text: "" });
        if (item?.entry)
            out.push({ id: "pin", icon: pinned ? "keep_off" : "keep", text: pinned ? "Unpin from dock" : "Keep in dock" });
        if (running) {
            const n = item.toplevels.length;
            out.push({ id: "quit", icon: "close", text: n > 1 ? "Quit (" + n + " windows)" : "Quit" });
        }
        return out;
    }

    function run(row) {
        const id = row.id;
        if (id === "line")
            return;
        if (id === "new" && running && newWindow)
            DockState.launchAction(item, newWindow);
        else if (id === "new")
            DockState.launch(item);
        else if (id === "action")
            DockState.launchAction(item, row.action);
        else if (id === "pin")
            DockState.togglePin(item.key);
        else if (id === "quit")
            DockState.closeAll(item);
        done();
    }

    implicitWidth: Math.max(190, column.implicitWidth + 12)
    implicitHeight: column.implicitHeight + 12

    // Dark on the dark dock (Style.dockDark), as DockPreview.
    Glass {
        anchors.fill: parent
        radius: 18
        color: Style.dockDark && Style.barIslandCards ? Style.alpha(Colors.surfaceContainerLowest, Style.barIslandCardOpacity)
            : Style.alpha(Colors.surfaceContainer, 0.92)
        rimScale: Style.dockDark && Style.barIslandCards ? 0 : 1
        border.color: Style.dockDark && Style.barIslandCards ? Style.alpha(Style.islandBorder, Math.min(Style.islandBorder.a, 0.06))
            : liquid ? Style.glassBorder : Style.islandBorder
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
            text: DockState.title(root.item)
            weight: 700
            elide: Text.ElideRight
        }

        Repeater {
            model: root.actions

            MouseArea {
                id: row
                required property var modelData
                readonly property bool line: modelData.id === "line"

                width: column.width
                height: line ? 9 : 34
                enabled: !line
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.run(modelData)

                // The line between the app's own actions and the dock's.
                Rectangle {
                    visible: row.line
                    x: 10
                    width: parent.width - 20
                    height: 1
                    anchors.verticalCenter: parent.verticalCenter
                    color: Style.alpha(Colors.textOnSurface, 0.12)
                }

                Rectangle {
                    visible: !row.line
                    anchors.fill: parent
                    radius: 12
                    color: row.modelData.id === "quit" ? Colors.error : Colors.textOnSurface
                    opacity: row.pressed ? Style.pressTint : row.containsMouse ? Style.hoverTint : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                Row {
                    visible: !row.line
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: row.modelData.icon
                        size: 18
                        color: row.modelData.id === "quit" ? Colors.error : Colors.textOnSurfaceVariant
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.text
                        color: row.modelData.id === "quit" ? Colors.error : Colors.textOnSurface
                    }
                }
            }
        }
    }
}
