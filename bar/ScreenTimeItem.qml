import QtQuick
import Quickshell
import qs.common
import qs.services

// Screen time (services/ScreenTime.qml): today's time on the screen, "3h 12m";
// during a break (services/Breaks.qml) the countdown instead. Click: the
// popup with each app, the last 7 days and the break reminders.
Reveal {
    id: root

    // (`wanted`: the bar's slot reads it, see BarContent.)
    readonly property bool wanted: shown || implicitWidth > 0.5

    anchors.verticalCenter: parent?.verticalCenter
    shown: ScreenTime.enabled || Breaks.showing

    // Today's total moves on once a minute (and whenever a stretch ends).
    property real now: Date.now()
    Timer {
        interval: 60000
        running: root.shown
        repeat: true
        onTriggered: root.now = Date.now()
    }
    readonly property real today: ScreenTime.totalOn(ScreenTime.dayKey(now), now + ScreenTime.revision * 0)
    readonly property bool onBreak: Breaks.phase === "break"
    readonly property string countdown: {
        const s = Math.ceil(Breaks.breakLeft / 1000);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    Clickable {
        id: button
        spacing: 5
        tip: root.onBreak ? "On a break" : "Screen time"
        tipDetail: (root.onBreak ? root.countdown + " left" : ScreenTime.durationText(root.today, false) + " today")
            + (Breaks.enabled && !root.onBreak ? " · break reminders on" : "")
            + "\nClick: per app and the last 7 days"
        onClicked: {
            const win = button.QsWindow.window;
            BarPopupState.toggle("screentime", win?.screen?.name ?? "",
                                 win ? win.itemRect(button) : Qt.rect(0, 0, 0, 0));
        }

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.onBreak ? "self_improvement" : "hourglass_bottom"
            size: 16
            color: root.onBreak ? Colors.primary : Colors.textOnSurface
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.onBreak ? root.countdown : ScreenTime.durationText(root.today, true)
            font.features: ({ "tnum": 1 })
        }
    }
}
