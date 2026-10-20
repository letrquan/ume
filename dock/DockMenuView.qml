import QtQuick
import qs.common

// What the right-click menu of a dock icon shows:
//   Firefox
//   ＋ New window
//   📌 Unpin from dock
//   ✕ Quit (2 windows)
// Plain QtQuick, so it can be previewed outside the shell.
Item {
    id: root

    property var item: null
    signal done()

    readonly property bool running: (item?.toplevels.length ?? 0) > 0
    readonly property bool pinned: item ? DockState.isPinned(item.key) : false
    readonly property var actions: {
        const out = [];
        if (item?.entry)
            out.push({ id: "new", icon: running ? "add" : "play_arrow", text: running ? "New window" : "Open" });
        if (item?.entry)
            out.push({ id: "pin", icon: pinned ? "keep_off" : "keep", text: pinned ? "Unpin from dock" : "Keep in dock" });
        if (running) {
            const n = item.toplevels.length;
            out.push({ id: "quit", icon: "close", text: n > 1 ? "Quit (" + n + " windows)" : "Quit" });
        }
        return out;
    }

    function run(id) {
        if (id === "new")
            DockState.launch(item);
        else if (id === "pin")
            DockState.togglePin(item.key);
        else if (id === "quit")
            DockState.closeAll(item);
        done();
    }

    implicitWidth: Math.max(190, column.implicitWidth + 12)
    implicitHeight: column.implicitHeight + 12

    Glass {
        anchors.fill: parent
        radius: 18
        color: Style.alpha(Colors.surfaceContainer, 0.92)
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

                width: column.width
                height: 34
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.run(modelData.id)

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: row.modelData.id === "quit" ? Colors.error : Colors.textOnSurface
                    opacity: row.pressed ? Style.pressTint : row.containsMouse ? Style.hoverTint : 0
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
