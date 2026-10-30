import QtQuick
import qs.common
import qs.services

// The timer on the bar (services/Timers.qml; "Timer" in Bar items), only
// while one runs, is paused, or something rings: an hourglass and the time
// left (dimmed while paused), or a ringing bell. It slides in and out.
// Click: pause / go on, or stop the ringing. Right click: cancel.
Reveal {
    id: root

    readonly property bool wanted: shown || implicitWidth > 0.5
    readonly property bool rings: Timers.ringing

    anchors.verticalCenter: parent?.verticalCenter
    shown: Timers.timerState !== "idle" || rings

    Clickable {
        spacing: 5
        tip: root.rings ? Timers.ringTitle : Timers.timerState === "paused" ? "Timer paused" : "Timer"
        tipDetail: root.rings ? "Click: stop" : "Click: " + (Timers.timerState === "paused" ? "go on" : "pause") + " · right-click: cancel"
        onClicked: mouse => {
            if (root.rings)
                Timers.stopRing();
            else if (mouse.button === Qt.RightButton)
                Timers.cancelTimer();
            else
                Timers.toggleTimer();
        }

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.rings ? "notifications_active" : "hourglass_top"
            size: Style.iconSize - 2
            color: root.rings ? Colors.primary : Colors.textOnSurfaceVariant

            SequentialAnimation on rotation {
                running: root.rings
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 14; duration: 90 }
                NumberAnimation { to: -14; duration: 180 }
                NumberAnimation { to: 0; duration: 90 }
                PauseAnimation { duration: 500 }
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.rings
            text: Timers.timerText
            font.features: ({ "tnum": 1 })
            weight: 650
            opacity: Timers.timerState === "paused" ? 0.55 : 1

            Behavior on opacity { NumberAnimation { duration: Motion.normal } }
        }
    }
}
