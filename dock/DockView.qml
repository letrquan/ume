import QtQuick
import Quickshell
import qs.common

// Everything you see of the dock: a glass bar at the bottom middle with the
// app icons (near-black like the bar's middle island with Style.dockDark). Icons near the pointer grow (macOS style), the ones further
// away less; a glass label shows the name of the one under the pointer.
// Resting on a running app brings up a card with its windows
// (DockPreview.qml) instead of the label.
// Plain QtQuick, so it can be previewed outside the shell.
Item {
    id: root

    // The part that takes clicks: the bar, plus the grown icons above it
    // while the pointer is on the dock.
    readonly property alias hitArea: hitArea
    // The window preview card (also takes clicks while it's out).
    readonly property alias previewCard: preview
    // Right click on an icon: Dock.qml opens the menu.
    signal menuRequested(var slot)

    // For previews: pretend the pointer is this far from the dock's middle.
    property real previewPointer: NaN
    // The right-click menu is open (no name label then).
    property bool menuOpen: false
    // 0 = out, 1 = slid away below the screen edge (DockReveal).
    property real slide: 0
    // The pointer is on the bar (or the grown icons), or on the preview card.
    readonly property bool hovered: hover.hovered || preview.hovered
    // Pictures of the windows on the preview card (off in offscreen previews).
    property bool previewCapture: true

    readonly property real iconSize: Style.dockIconSize
    readonly property real barHeight: iconSize + Style.dockPaddingCross * 2
    readonly property real rowHeight: iconSize * Style.dockMagnify + 2
    // The room between pinned and running-only apps: a thin line, or on the
    // dark dock just space (as the bar has no dividers).
    readonly property real dividerWidth: Style.dockDark ? 6 : 1
    readonly property bool pointing: !isNaN(previewPointer) || hover.hovered || preview.hovered
    // Pointer distance from the screen's middle (the dock is centred there).
    // Measured against the screen, not the dock: the dock widens as icons
    // grow, which would move the measurement and feed back into the sizes.
    // On the preview card the icons stay as they were when the pointer left
    // the dock, so the card doesn't move under it.
    readonly property real livePointer: hover.point.scenePosition.x - (root.x + root.width / 2)
    property real heldPointer: 0
    onLivePointerChanged: if (hover.hovered) heldPointer = livePointer
    readonly property real pointerOffset: !isNaN(previewPointer) ? previewPointer
        : hover.hovered ? livePointer : heldPointer

    // 0 → 1 as the pointer arrives, so the icons grow in and shrink out
    // instead of jumping.
    property real growth: pointing ? 1 : 0
    Behavior on growth {
        NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
    }

    // ---- Magnification ---------------------------------------------------------------
    // Where each icon would be with nothing grown; the pointer is measured
    // against that, so the icons growing never move the target under it.
    readonly property var baseCenters: {
        const out = [];
        let x = 0;
        for (const key of DockState.keys) {
            const w = key === "|" ? dividerWidth : iconSize;
            out.push(x + w / 2);
            x += w + Style.dockSpacing;
        }
        return out;
    }
    readonly property real baseWidth: baseCenters.length === 0 ? 0
        : DockState.keys.length * Style.dockSpacing - Style.dockSpacing
          + DockState.keys.reduce((sum, key) => sum + (key === "|" ? dividerWidth : iconSize), 0)

    function scaleFor(index) {
        if (growth <= 0.001 || DockState.keys[index] === "|")
            return 1;
        // Same distance from the middle as on the real (grown) dock.
        const pointer = baseWidth / 2 + pointerOffset;
        const distance = Math.abs(pointer - baseCenters[index]);
        const reach = iconSize * Style.dockMagnifyRange;
        const near = distance >= reach ? 0 : (Math.cos(distance / reach * Math.PI) + 1) / 2;
        return 1 + (Style.dockMagnify - 1) * near * growth;
    }

    // ---- Which icon the label is for -------------------------------------------------
    property var hoveredSlot: null
    function setHovered(slot, on) {
        if (on)
            hoveredSlot = slot;
        else if (hoveredSlot === slot)
            hoveredSlot = null;
    }

    // ---- Window previews ---------------------------------------------------------------
    // The icon whose card is out (null: none). Resting on a running app's
    // icon for Style.dockPreviewDelay brings it out; once one is out, moving
    // to another running app swaps it at once. Leaving both the icon and the
    // card puts it away after a moment (time to cross the gap between them).
    property var previewSlot: null
    // A click on the icon puts the card away until the pointer leaves it.
    property var previewBlocked: null
    readonly property bool previewing: previewSlot !== null

    function wantsPreview(slot) {
        return Style.dockPreviews && !menuOpen && slot !== null && slot !== previewBlocked
            && (slot.item?.toplevels.length ?? 0) > 0;
    }
    function dismissPreview() {
        previewBlocked = hoveredSlot;
        previewSlot = null;
        previewOpen.stop();
    }

    onHoveredSlotChanged: {
        if (hoveredSlot !== previewBlocked)
            previewBlocked = null;
        if (wantsPreview(hoveredSlot)) {
            previewClose.stop();
            if (previewing)
                previewSlot = hoveredSlot;
            else
                previewOpen.restart();
        } else {
            previewOpen.stop();
            if (previewing)
                previewClose.restart();
        }
    }
    onMenuOpenChanged: if (menuOpen) dismissPreview()

    Timer {
        id: previewOpen
        interval: Style.dockPreviewDelay
        onTriggered: if (root.wantsPreview(root.hoveredSlot)) root.previewSlot = root.hoveredSlot
    }
    Timer {
        id: previewClose
        interval: 300
        onTriggered: if (!preview.hovered && !root.wantsPreview(root.hoveredSlot)) root.previewSlot = null
    }
    // Leaving the card: the same moment of grace.
    Connections {
        target: preview
        function onHoveredChanged() {
            if (!preview.hovered && root.previewing && !root.wantsPreview(root.hoveredSlot))
                previewClose.restart();
        }
    }
    // The app's last window closed: nothing left to show.
    Connections {
        target: root.previewSlot
        function onWindowsChanged() {
            if (root.previewSlot && root.previewSlot.windows === 0)
                root.previewSlot = null;
        }
    }

    // ---- The way in (common/Intro.qml) -----------------------------------------------------
    // After the wallpaper and a beat after the bar: the bar rises from just
    // below and fades in. Only what you see moves; its place (and click
    // area) is right from the start.
    property real introY: Intro.started && !Intro.enabled ? 0 : 26
    property real introOpacity: Intro.started && !Intro.enabled ? 1 : 0
    ParallelAnimation {
        id: rise
        NumberAnimation {
            target: root; property: "introY"; to: 0; duration: Motion.slow
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial
        }
        NumberAnimation {
            target: root; property: "introOpacity"; to: 1; duration: Motion.normal
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects
        }
    }
    Timer {
        id: riseLater
        interval: Style.dropInDelay * 3
        onTriggered: rise.start()
    }
    function comeIn() {
        if (introOpacity < 1 && !rise.running && !riseLater.running)
            riseLater.start();
    }
    Component.onCompleted: if (Intro.started) comeIn()
    Connections {
        target: Intro
        function onStartedChanged() {
            if (Intro.started)
                root.comeIn();
        }
    }

    // ---- The bar -----------------------------------------------------------------------
    Item {
        id: hitArea

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.dockMarginEdge - root.slide * (Style.dockMarginEdge + root.barHeight + 2)
        width: row.width + Style.dockPaddingMain * 2
        height: root.barHeight + (root.pointing ? root.rowHeight - root.iconSize : 0)

        HoverHandler {
            id: hover
        }

        Glass {
            id: bar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.barHeight
            opacity: root.introOpacity
            transform: Translate { y: root.introY }
            radius: Style.dockRadius
            color: Style.dockDark ? Style.alpha(Colors.surfaceContainerLowest, Style.barIslandOpacity)
                : Style.alpha(Colors.surfaceContainer, Style.dockOpacity)
            // Dark: as the bar's middle island (Island.qml), a faint edge
            // and no light on it.
            liquid: !Style.dockDark && Style.glassStyle === "liquid"
            sheen: !Style.dockDark
            border.color: Style.dockDark ? "#0affffff" : liquid ? Style.glassBorder : Style.islandBorder
        }

        Row {
            id: row
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.dockPaddingCross
            spacing: Style.dockSpacing
            opacity: root.introOpacity
            transform: Translate { y: root.introY }

            Repeater {
                model: ScriptModel {
                    values: DockState.keys
                }

                DockItem {
                    view: root
                }
            }
        }
    }

    // ---- Name label --------------------------------------------------------------------
    Item {
        id: label

        readonly property var slot: root.hoveredSlot
        property string text: ""
        onSlotChanged: if (slot) text = DockState.title(slot.item)

        // Over the middle of the icon, just above its top (follows it as it grows).
        x: slot ? Math.round(hitArea.x + row.x + slot.x + slot.width / 2 - width / 2) : x
        y: slot ? Math.round(hitArea.y + row.y + slot.y + slot.height - slot.size - height - 10) : y
        width: name.implicitWidth + 22
        height: 28
        opacity: slot && !root.menuOpen && !root.previewing ? 1 : 0
        scale: slot && !root.menuOpen && !root.previewing ? 1 : 0.9

        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }

        // A little island of its own: dark on the dark dock.
        Glass {
            anchors.fill: parent
            radius: height / 2
            color: Style.dockDark ? Style.alpha(Colors.surfaceContainerLowest, Style.barIslandOpacity)
                : Style.alpha(Colors.surfaceContainer, 0.85)
            liquid: !Style.dockDark && Style.glassStyle === "liquid"
            sheen: !Style.dockDark
            border.color: Style.dockDark ? "#0affffff" : liquid ? Style.glassBorder : Style.islandBorder
        }

        StyledText {
            id: name
            anchors.centerIn: parent
            text: label.text
            role: "label"
        }
    }

    // ---- Window preview card ---------------------------------------------------------------
    DockPreview {
        id: preview

        readonly property var slot: root.previewSlot
        item: slot?.item ?? null
        capture: root.previewCapture

        // Over the middle of the icon, just above its top; kept on screen.
        x: slot ? Math.round(Math.max(8, Math.min(root.width - width - 8,
               hitArea.x + row.x + slot.x + slot.width / 2 - width / 2))) : x
        y: slot ? Math.round(hitArea.y + row.y + slot.y + slot.height - slot.size - height - 12) : y

        Behavior on x {
            enabled: preview.visible
            NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
        }

        onPicked: root.dismissPreview()
    }
}
