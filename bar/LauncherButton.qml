import QtQuick
import qs.common
import qs.services

// App launcher button: a Material shape that morphs and turns on hover.
// Opens the launcher (the middle island turns into a search bar).
Clickable {
    id: root

    tip: "Launcher"
    tipDetail: "Apps, files, emoji, math and the web"
    tipShortcut: "mine:launcher"
    onClicked: LauncherState.toggle()

    Shape {
        width: 18
        height: 18
        // (The shell's mark: it keeps its shape with simple shapes too.)
        keep: true
        shape: root.containsMouse ? "Sunny" : "Cookie7Sided"
        color: Colors.primary
        rotation: root.containsMouse ? 60 : 0

        Behavior on rotation {
            NumberAnimation {
                duration: Motion.normal
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.defaultSpatial
            }
        }
    }
}
