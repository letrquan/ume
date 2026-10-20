import QtQuick
import Quickshell
import qs.common
import qs.services

// Workspace slots. Taken ones (with windows) share a soft background, the
// current one is a primary pill that stretches as it slides to the next
// slot. Click a slot to go there, scroll to move left/right.
// With Style.workspaceIcons, a taken slot shows the icons of its apps
// (up to Style.workspaceIconsMax, then "+n") instead of its number, and
// grows to fit them; the pill grows with it.
Item {
    id: root

    required property var mango     // MangoMonitor of this screen

    readonly property real slot: Style.workspaceSlot
    readonly property int activeIndex: mango.activeTag - 1
    readonly property bool showIcons: Style.workspaceIcons
    readonly property int iconSize: Math.round(slot * 2 / 3)
    readonly property int iconGap: 3
    // Room between two slots (only with icons; numbers sit edge to edge).
    readonly property int cellGap: showIcons ? 3 : 0
    // Always show `workspacesShown` slots, more when a later one is in use.
    readonly property int count: {
        let n = Style.workspacesShown;
        for (const t of mango.tags)
            if (t.clients > 0 || t.active)
                n = Math.max(n, t.index);
        return n;
    }
    // Runs of neighbouring taken slots, each drawn as one soft pill (with
    // icons, every taken slot is a pill of its own, so their apps don't run
    // together): [{ start: 0-based slot, length }]
    readonly property var runs: {
        const out = [];
        for (let i = 0; i < count; i++) {
            const t = mango.tags[i];
            if (t === undefined || t.clients === 0)
                continue;
            const last = out[out.length - 1];
            if (last && last.start + last.length === i && !showIcons)
                last.length++;
            else
                out.push({ start: i, length: 1 });
        }
        return out;
    }

    // The window titles on workspace `tag` (1-based), for its tip: from
    // mango's window list (MangoClients), a terminal's spinner left out.
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

    function taken(i) {
        const t = mango.tags[i];
        return t !== undefined && t.clients > 0;
    }

    // The apps on slot i (0-based): [{ appId, icon }].
    function appsAt(i) {
        return showIcons ? MangoClients.appsOn(mango.monitor, i + 1) : [];
    }

    // Slot i as drawn right now (its width animates when apps come and go).
    function cellAt(i) {
        cellRepeater.count;
        return cellRepeater.itemAt(Math.max(0, Math.min(i, cellRepeater.count - 1)));
    }
    // Left / right edge at a slot position that may be in between two
    // slots (the pill's ends slide through them).
    function edgeAt(f, right) {
        const i = Math.floor(f);
        const a = cellAt(i), b = cellAt(i + 1);
        if (!a)
            return 0;
        const ea = right ? a.x + a.width : a.x;
        const eb = b ? (right ? b.x + b.width : b.x) : ea;
        return ea + (eb - ea) * (f - i);
    }
    // Where everything settles (for the bar's size).
    readonly property real targetWidth: {
        let w = Math.max(0, cellRepeater.count - 1) * cellGap;
        for (let i = 0; i < cellRepeater.count; i++)
            w += cellRepeater.itemAt(i)?.target ?? slot;
        return w;
    }

    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: targetWidth + 4
    implicitHeight: Style.itemHeight

    Behavior on implicitWidth {
        NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
    }

    Component.onCompleted: MangoClients.use(1)
    Component.onDestruction: MangoClients.use(-1)

    // The pill's two ends follow the active slot at different speeds,
    // so it stretches on the way and settles at the end.
    property real lead: activeIndex
    property real trail: activeIndex
    Behavior on lead {
        NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
    }
    Behavior on trail {
        NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
    }

    // Scrolling anywhere on the workspaces. Touchpads scroll in small steps:
    // add them up to one notch first.
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

    Item {
        id: slots
        x: 2
        width: cells.width
        height: root.slot
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            model: root.runs

            Rectangle {
                required property var modelData
                readonly property var first: root.cellAt(modelData.start)
                readonly property var last: root.cellAt(modelData.start + modelData.length - 1)
                x: first?.x ?? 0
                width: (last ? last.x + last.width : 0) - x
                height: root.slot
                radius: height / 2
                color: Style.alpha(Colors.secondary, 0.2)
                opacity: 0
                Component.onCompleted: opacity = 1

                Behavior on opacity {
                    NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
                }
            }
        }

        // The current workspace.
        Rectangle {
            x: Math.min(root.edgeAt(root.lead, false), root.edgeAt(root.trail, false))
            width: Math.max(root.edgeAt(root.lead, true), root.edgeAt(root.trail, true)) - x
            height: root.slot
            radius: height / 2
            color: Colors.primary
        }

        // Numbers (or app icons) on taken / current slots, small dots on
        // empty ones.
        Row {
            id: cells
            spacing: root.cellGap

            Behavior on spacing {
                NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
            }

            Repeater {
                id: cellRepeater
                model: root.count

                Item {
                    id: cell

                    required property int index
                    readonly property var tag: root.mango.tags[index]
                    readonly property bool active: index === root.activeIndex
                    readonly property bool busy: root.taken(index)
                    readonly property bool urgent: tag?.urgent ?? false
                    readonly property var apps: root.appsAt(index)
                    readonly property int shown: Math.min(apps.length, Math.max(1, Style.workspaceIconsMax))
                    readonly property int more: apps.length - shown
                    readonly property bool withIcons: shown > 0
                    // The width it settles at: one icon fits the plain slot.
                    readonly property real target: !withIcons ? root.slot
                        : root.slot - root.iconSize + shown * root.iconSize + (shown - 1) * root.iconGap
                          + (more > 0 ? plus.implicitWidth + root.iconGap : 0)

                    width: target
                    height: root.slot

                    // Its tip: the workspace, its keys, what's open on it.
                    TipArea {
                        id: cellTip
                        tip: "Workspace " + (cell.index + 1)
                        tipShortcut: "func:view," + (cell.index + 1)
                        tipDetail: {
                            if (Tooltips.source !== cellTip)
                                return "";
                            const titles = root.titlesOn(cell.index + 1);
                            const n = cell.tag?.clients ?? titles.length;
                            if (titles.length === 0)
                                return n > 0 ? n + (n === 1 ? " window" : " windows") : "Empty";
                            const shown = titles.slice(0, 6);
                            return shown.join("\n") + (titles.length > 6 ? "\n+" + (titles.length - 6) + " more" : "");
                        }
                    }

                    Behavior on width {
                        NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: cell.index + 1
                        role: "label"
                        weight: cell.active ? 700 : 600
                        color: cell.active ? Colors.textOnPrimary
                             : cell.urgent ? Colors.error
                             : Colors.textOnSurface
                        opacity: !cell.withIcons && (cell.active || cell.busy || cell.urgent) ? 1 : 0
                        scale: opacity > 0 ? 1 : 0.5

                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        Behavior on scale {
                            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: hover.containsMouse ? 7 : 5
                        height: width
                        radius: width / 2
                        color: Colors.textOnSurfaceVariant
                        opacity: cell.withIcons || cell.active || cell.busy || cell.urgent ? 0 : (hover.containsMouse ? 0.9 : 0.4)

                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        Behavior on width {
                            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                        }
                    }

                    // The apps' icons, centred; "+2" when there are more.
                    Row {
                        anchors.centerIn: parent
                        spacing: root.iconGap
                        opacity: cell.withIcons ? (cell.active || hover.containsMouse ? 1 : 0.85) : 0
                        scale: cell.withIcons ? 1 : 0.5

                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        Behavior on scale {
                            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                        }

                        Repeater {
                            model: cell.apps.slice(0, cell.shown)

                            AppIcon {
                                required property var modelData
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: root.iconSize
                                source: modelData.icon
                                name: modelData.appId
                                // A see-through dark tile: sits as well on the
                                // active pill as on the glass, so it doesn't
                                // change while the pill slides by.
                                tileColor: Style.alpha(Colors.shadow, 0.22)
                            }
                        }

                        StyledText {
                            id: plus
                            anchors.verticalCenter: parent.verticalCenter
                            visible: cell.more > 0
                            text: "+" + cell.more
                            role: "micro"
                            color: cell.active ? Colors.textOnPrimary : Colors.textOnSurfaceVariant
                        }
                    }

                    // Something on it wants attention (icons hide the red number).
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 1
                        width: 6
                        height: 6
                        radius: 3
                        color: Colors.error
                        visible: cell.withIcons && cell.urgent
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: Tooltips.press(cellTip)
                        onClicked: root.mango.view(cell.index + 1)
                    }
                }
            }
        }
    }
}
