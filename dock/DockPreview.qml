import QtQuick
import QtQuick.Window
import Quickshell
import qs.common
import qs.services

// The card that pops up over a running app after the pointer rests on its
// icon (Style.dockPreviewDelay): a live picture of each of its windows,
// title under it. Click one to go there, middle-click or ✕ to close it.
// Pictures (services/WindowShots.qml) are only taken while the card is out:
// once when it comes out, then about every second.
Item {
    id: root

    property var item: null          // DockState item while the card is out
    property bool capture: true      // false: icons instead of pictures (previews)
    readonly property bool shown: item !== null
    readonly property bool hovered: hover.hovered

    // A window was picked: DockView puts the card away.
    signal picked()

    // Keep showing the last app while the card fades out.
    property var held: null
    onItemChanged: if (item) held = item
    // Faded out: let the pictures go.
    onVisibleChanged: if (!visible && !item) held = null

    // At most 6 windows, fewer if their pictures wouldn't fit across the
    // screen (big Style.dockPreviewSize); more show as "+N".
    readonly property int maxWindows: Math.max(1, Math.min(6,
        Math.floor(((parent?.width ?? 1536) - 100) / (Style.dockPreviewSize * 1.6 + 10))))
    readonly property var windows: (held?.toplevels ?? []).slice(0, maxWindows)
    readonly property int more: Math.max(0, (held?.toplevels.length ?? 0) - maxWindows)

    width: row.width + 24
    height: row.height + 24
    visible: opacity > 0.01
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.92
    transformOrigin: Item.Bottom

    Behavior on opacity {
        NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
    }
    Behavior on scale {
        NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
    }
    Behavior on width {
        NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
    }

    HoverHandler {
        id: hover
    }

    // ---- Pictures ---------------------------------------------------------------------
    // The last pictures show at once (WindowShots keeps them); new ones
    // while the card is out, each about as tall as it's shown.
    readonly property bool taking: capture && shown
    onTakingChanged: {
        if (taking) {
            WindowShots.use(1);
            WindowShots.lookup();
        }
    }
    function shoot() {
        // The window's own pixel ratio (1.25 here; Screen's is 2).
        const dpr = QsWindow.window?.devicePixelRatio || Screen.devicePixelRatio || 1;
        WindowShots.capture(windows.map(t => WindowShots.infoFor(t)).filter(i => i)
            .map(i => ({ id: i.ftid, scale: Style.dockPreviewSize * dpr / i.height, kind: "dock" })));
    }
    // mango's list came in (or the app's windows changed): take them now.
    Connections {
        target: WindowShots
        enabled: root.taking
        function onClientsChanged() { root.shoot(); }
    }
    onWindowsChanged: if (taking) WindowShots.lookup()
    Timer {
        interval: 1000
        running: root.taking
        repeat: true
        onTriggered: root.shoot()
    }

    // Out of the dark dock (Style.dockDark): dark too, as the cards out of
    // the bar's middle island (MorphCard).
    Glass {
        anchors.fill: parent
        radius: 20
        color: Style.dockDark && Style.barIslandCards ? Style.alpha(Colors.surfaceContainerLowest, Style.barIslandCardOpacity)
            : Style.alpha(Colors.surfaceContainer, 0.85)
        rimScale: Style.dockDark && Style.barIslandCards ? 0 : 1
        border.color: Style.dockDark && Style.barIslandCards ? Style.alpha(Style.islandBorder, Math.min(Style.islandBorder.a, 0.06))
            : liquid ? Style.glassBorder : Style.islandBorder
    }

    Row {
        id: row
        x: 12
        y: 12
        spacing: 10

        Repeater {
            // Same windows keep their picture when the list changes.
            model: ScriptModel {
                values: root.windows
            }

            DockThumb {
                app: root.held
                // Pictures only while the card is out (or fading).
                pictures: root.capture && root.visible
                onPicked: root.picked()
            }
        }

        // More windows than fit.
        Item {
            visible: root.more > 0
            width: 48
            height: Style.dockPreviewSize

            StyledText {
                anchors.centerIn: parent
                text: "+" + root.more
                weight: 650
                color: Colors.textOnSurfaceVariant
            }
        }
    }
}
