import QtQuick
import Quickshell
import qs.common
import qs.services

// The time, big, with rolling digits like on the lock screen; the date
// quieter next to it, and your next event when it's within the hour.
// Click: the calendar (with your events and the weather).
// Style.clock24h false: 12-hour time with a small AM/PM.
Clickable {
    id: root

    readonly property date now: clock.date
    readonly property var dateLocale: Style.clockLocale !== "" ? Qt.locale(Style.clockLocale) : Qt.locale()
    // "hh AP" is 12-hour only with the AM/PM in the same format.
    readonly property string time12: dateLocale.toString(now, "hh AP")
    readonly property string hh: Style.clock24h ? Qt.formatTime(now, "HH") : time12.substring(0, 2)
    readonly property string mm: Qt.formatTime(now, "mm")

    property font digitFont
    digitFont.family: Style.font
    digitFont.pixelSize: Style.clockSize
    digitFont.variableAxes: ({ "wght": 700, "ROND": 100 })
    digitFont.features: ({ "tnum": 1 })

    spacing: 9
    padding: 10
    // The whole date, its week, and your next event today.
    tip: dateLocale.toString(now, "dddd, d MMMM yyyy")
    tipDetail: "Week " + root.week(now)
        + (Events.soon ? "\nNext: " + Events.time(Events.soon.start) + "  " + Events.soon.title : "")
    onClicked: CalendarState.toggle()

    // ISO week number (weeks start on Monday; week 1 has the year's first
    // Thursday).
    function week(d) {
        const t = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        t.setDate(t.getDate() + 3 - (t.getDay() + 6) % 7);
        const first = new Date(t.getFullYear(), 0, 4);
        return 1 + Math.round(((t - first) / 86400000 - 3 + (first.getDay() + 6) % 7) / 7);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter

        RollingDigit { digit: root.hh[0]; font: root.digitFont }
        RollingDigit { digit: root.hh[1]; font: root.digitFont }
        Text {
            text: ":"
            font: root.digitFont
            color: Colors.primary
            renderType: Text.NativeRendering
        }
        RollingDigit { digit: root.mm[0]; font: root.digitFont }
        RollingDigit { digit: root.mm[1]; font: root.digitFont }
    }

    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        visible: !Style.clock24h
        text: root.time12.substring(3)
        role: "micro"
        color: Colors.primary
    }

    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        visible: text !== ""
        text: root.dateLocale.toString(root.now, Style.clockDate)
        font.pixelSize: Style.textSize("label")
        color: Colors.textOnSurfaceVariant
    }

    // Your next event, when it starts within the hour (Events).
    Row {
        anchors.verticalCenter: parent.verticalCenter
        visible: Style.clockNextEvent && Events.soon !== null
        spacing: 5

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "event"
            size: Style.fontSize + 1
            color: Colors.primary
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 170)
            text: Events.soon ? Events.time(Events.soon.start) + "  " + Events.soon.title : ""
            role: "label"
            elide: Text.ElideRight
        }
    }
}
