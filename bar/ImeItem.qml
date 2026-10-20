import QtQuick
import qs.common

// The typing language as a small key cap, "EN" or "VI": how the tray draws
// fcitx5's icon (bar/TrayItem.qml; which one is on: OsdState.imeCode).
// Vietnamese is filled, English outlined, so they're told apart at a glance.
Rectangle {
    id: root

    property string code: "EN"
    readonly property bool filled: code === "VI"

    implicitWidth: Math.max(label.implicitWidth + 8, 22)
    implicitHeight: 16
    radius: 5
    color: filled ? Colors.primary : "transparent"
    border.width: filled ? 0 : 1.5
    border.color: Style.alpha(Colors.textOnSurface, 0.75)

    Behavior on color { ColorAnimation { duration: Motion.fast } }

    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.code
        role: "micro"
        weight: 750
        color: root.filled ? Colors.textOnPrimary : Colors.textOnSurface
    }
}
