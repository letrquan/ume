import QtQuick
import Quickshell
import qs.common
import qs.services

// Workspaces as dots (Style.workspaceStyle "dots"): one per slot, bright
// while it has windows, faint while empty; the current one is a longer
// pill in the accent color that stretches over to the next one. Click a
// dot to go there, scroll to move left/right; hover: what's open on it.
// (bar/Workspaces.qml is the other style: numbers or app icons.)
Item {
    id: root

    required property var mango     // MangoMonitor of this screen

    readonly property int activeIndex: mango.activeTag - 1
    readonly property real dot: 6
    readonly property real pill: 20
    readonly property real gap: 6
    // Each dot sits in a cell this wide, so it's easy to hit.
    readonly property real cell: dot + gap
    // Always show `workspacesShown` dots, more when a later one is in use.
    readonly property int count: {
        let n = Style.workspacesShown;
        for (const t of mango.tags)
            if (t.clients > 0 || t.active)
                n = Math.max(n, t.index);
        return n;
    }

    // The window titles on workspace `tag` (1-based), for its tip (as in
    // Workspaces.qml).
    function titlesOn(tag) {
        let list = [];
        try {
            list = JSON.parse(MangoClients.lastLine || "{}").clients ?? [];
        } catch (e) {
            return [];
        }
        return list.filter(c => c.monitor === mango.monitor && (c.tags ?? []).includes(tag) && !c.is_scratchpad && !c.is_namedscratchpad)
                   .sort((a, b) => a.id - b.id)
                   .map(c => (c.title || c.appid || "").replace(/^[·✢✳✶✻✽◐-◓⠀-⣿]+\s+(?=\S)/, ""));
    }

    // The window list (for the tips) runs while this is on the bar.
    Component.onCompleted: MangoClients.use(1)
    Component.onDestruction: MangoClients.use(-1)

    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: count * cell + (pill - dot)
    implicitHeight: Style.itemHeight

    // Scrolling anywhere on the dots; touchpads add up to one notch first.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        property real sum: 0
        onWheel: wheel => {
            sum += wheel.angleDelta.y || -wheel.angleDelta.x;
            if (sum >= 120) {
                root.mango.viewLeft();
                sum = 0;
            } else if (sum <= -120) {
                root.mango.viewRight();
                sum = 0;
            }
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: root.gap / 2

        Repeater {
            model: root.count

            Item {
                id: cellItem

                required property int index
                readonly property var tag: root.mango.tags[index]
                readonly property bool active: index === root.activeIndex
                readonly property bool busy: (tag?.clients ?? 0) > 0
                readonly property bool urgent: tag?.urgent ?? false

                width: (active ? root.pill : root.dot) + root.gap
                height: root.implicitHeight

                Behavior on width {
                    NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - root.gap
                    height: root.dot
                    radius: root.dot / 2
                    color: cellItem.active ? Colors.primary : cellItem.urgent ? Colors.error : Colors.textOnSurface
                    opacity: cellItem.active || cellItem.urgent ? 1 : cellItem.busy ? 0.85 : 0.28

                    Behavior on color { ColorAnimation { duration: Motion.normal } }
                    Behavior on opacity { NumberAnimation { duration: Motion.normal } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.mango.view(cellItem.index + 1)
                }

                // Its tip: the workspace, its keys, what's open on it.
                TipArea {
                    id: cellTip
                    tip: "Workspace " + (cellItem.index + 1)
                    tipShortcut: "func:view," + (cellItem.index + 1)
                    tipDetail: {
                        if (Tooltips.source !== cellTip)
                            return "";
                        const titles = root.titlesOn(cellItem.index + 1);
                        const n = cellItem.tag?.clients ?? titles.length;
                        if (titles.length === 0)
                            return n > 0 ? n + (n === 1 ? " window" : " windows") : "Empty";
                        const shown = titles.slice(0, 6);
                        return shown.join("\n") + (titles.length > 6 ? "\n+" + (titles.length - 6) + " more" : "");
                    }
                }
            }
        }
    }
}
