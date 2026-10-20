import QtQuick
import Quickshell
import qs.common
import qs.services

// This month on the desktop, today marked, a dot under days with events;
// with a calendar set (Settings → Calendar & weather → Your events), today's
// events under it. Look only (click the bar's clock for the full calendar).
DesktopCard {
    id: root

    readonly property date today: clock.date
    readonly property var dateLocale: Style.clockLocale !== "" ? Qt.locale(Style.clockLocale) : Qt.locale()
    readonly property date month: new Date(today.getFullYear(), today.getMonth(), 1)

    // Six weeks, Monday first (like the calendar): { day, inMonth, isToday, date }.
    readonly property var cells: {
        const first = month;
        const lead = (first.getDay() + 6) % 7;
        const weeks = Math.ceil((lead + new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()) / 7);
        const out = [];
        for (let i = 0; i < weeks * 7; i++) {
            const d = new Date(first.getFullYear(), first.getMonth(), 1 - lead + i);
            out.push({
                day: d.getDate(),
                inMonth: d.getMonth() === first.getMonth(),
                isToday: d.toDateString() === today.toDateString(),
                date: d
            });
        }
        return out;
    }

    // Today's events (all-day first), at most three, and what comes next
    // when today is empty.
    readonly property var todays: Events.enabled && Events.revision >= 0 ? Events.on(today) : []
    readonly property var next: Events.enabled && todays.length === 0 && Events.revision >= 0
        ? Events.nextAfter(today.getTime(), true) : null

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    implicitWidth: 320
    implicitHeight: body.implicitHeight + padding * 2

    Column {
        id: body
        width: parent.width
        spacing: 8

        // October 2026
        StyledText {
            text: root.dateLocale.toString(root.month, "MMMM yyyy")
            role: "title"
        }

        Grid {
            id: grid
            columns: 7
            readonly property real cell: width / 7
            width: parent.width

            // M T W T F S S
            Repeater {
                model: [1, 2, 3, 4, 5, 6, 0]

                StyledText {
                    required property int modelData
                    width: grid.cell
                    horizontalAlignment: Text.AlignHCenter
                    text: root.dateLocale.dayName(modelData, Locale.NarrowFormat)
                    role: "micro"
                    color: Colors.textOnSurfaceVariant
                    bottomPadding: 4
                }
            }

            Repeater {
                model: root.cells

                Item {
                    id: day
                    required property var modelData
                    readonly property int events: Events.enabled && Events.revision >= 0 ? Events.count(modelData.date) : 0
                    width: grid.cell
                    height: 26

                    Shape {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        visible: day.modelData.isToday
                        shape: "Cookie9Sided"
                        color: Colors.primary
                    }
                    StyledText {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: day.events > 0 && !day.modelData.isToday ? -2 : 0
                        text: day.modelData.day
                        role: "caption"
                        font.features: ({ "tnum": 1 })
                        weight: day.modelData.isToday ? 750 : 500
                        color: day.modelData.isToday ? Colors.textOnPrimary : Colors.textOnSurface
                        opacity: day.modelData.inMonth ? 1 : 0.3
                    }
                    // A dot under days with events.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: 4
                        height: 4
                        radius: 2
                        visible: day.events > 0 && !day.modelData.isToday
                        color: Colors.primary
                        opacity: day.modelData.inMonth ? 1 : 0.4
                    }
                }
            }
        }

        // ---- Today ------------------------------------------------------------------------
        Rectangle {
            width: parent.width
            height: 1
            visible: Events.enabled
            color: Style.alpha(Colors.textOnSurface, 0.1)
        }

        Repeater {
            model: root.todays.slice(0, 3)

            Row {
                id: event
                required property var modelData
                width: body.width
                spacing: 8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 16
                    radius: 1.5
                    color: Events.colorOf(event.modelData.cal)
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 62
                    text: event.modelData.allDay ? "All day" : Events.time(event.modelData.start)
                    role: "caption"
                    font.features: ({ "tnum": 1 })
                    color: Colors.textOnSurfaceVariant
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: body.width - 62 - 3 - parent.spacing * 2
                    text: event.modelData.title
                    role: "label"
                    elide: Text.ElideRight
                }
            }
        }
        StyledText {
            visible: root.todays.length > 3
            text: "+" + (root.todays.length - 3) + " more today"
            role: "caption"
            color: Colors.textOnSurfaceVariant
        }
        StyledText {
            width: parent.width
            visible: Events.enabled && root.todays.length === 0
            text: root.next
                ? "Nothing today  ·  Next: " + root.dateLocale.toString(new Date(root.next.start), "ddd")
                  + (root.next.allDay ? "" : " " + Events.time(root.next.start)) + "  " + root.next.title
                : "Nothing today"
            role: "caption"
            color: Colors.textOnSurfaceVariant
            elide: Text.ElideRight
        }
    }
}
