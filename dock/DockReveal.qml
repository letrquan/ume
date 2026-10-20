import QtQuick
import qs.common

// When the dock is out (Style.dockBehavior):
//   "always"    always
//   "autohide"  while the pointer is on it (or at the bottom edge under it)
//               or its menu is open; it slides away Style.dockHideDelay ms
//               after the pointer leaves
//   "smart"     like autohide, but also while the workspace has no windows
// `slide` goes 0 (out) -> 1 (away); DockView moves the bar by it.
// Plain QtQuick (Dock.qml feeds it), so it can be tried outside the shell.
Item {
    id: root

    property string behavior: Style.dockBehavior
    property bool pointerHere: false
    property bool busy: false           // the right-click menu is open
    property int windowsHere: 0         // windows on the current workspace ("smart")

    readonly property bool hides: behavior === "autohide" || behavior === "smart"
    readonly property bool wanted: !hides || pointerHere || busy
        || (behavior === "smart" && windowsHere === 0)

    property bool shown: true
    property real slide: 0

    onWantedChanged: {
        if (wanted) {
            later.stop();
            shown = true;
        } else {
            later.restart();
        }
    }

    Timer {
        id: later
        interval: Style.dockHideDelay
        onTriggered: root.shown = root.wanted
    }

    // Out: decelerate into place; away: accelerate out of view.
    onShownChanged: {
        slider.stop();
        slider.to = shown ? 0 : 1;
        slider.duration = shown ? Motion.fast : Math.round(Motion.fast * 0.85);
        slider.easing.bezierCurve = shown ? Motion.emphasizedDecel : Motion.emphasizedAccel;
        slider.start();
    }

    NumberAnimation {
        id: slider
        target: root
        property: "slide"
        easing.type: Easing.BezierSpline
    }

    // Start where it belongs, without sliding.
    Component.onCompleted: {
        shown = wanted;
        slider.stop();
        slide = shown ? 0 : 1;
    }
}
