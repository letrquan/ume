import QtQuick
import qs.common

// This month, Monday first, today on a cookie (like the bar's calendar).
LockCard {
    id: root

    property date now: new Date()

    readonly property var dateLocale: Style.clockLocale !== "" ? Qt.locale(Style.clockLocale) : Qt.locale()
    readonly property date month: new Date(now.getFullYear(), now.getMonth(), 1)
    // Six weeks: { day, inMonth, isToday }.
    readonly property var cells: {
        const lead = (month.getDay() + 6) % 7;    // Monday = 0
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(month.getFullYear(), month.getMonth(), 1 - lead + i);
            out.push({
                day: d.getDate(),
                inMonth: d.getMonth() === month.getMonth(),
                isToday: d.toDateString() === now.toDateString()
            });
        }
        return out;
    }
    readonly property real cell: width > 32 ? (width - 32) / 7 : 0
    readonly property real rowHeight: Math.min(34, Math.max(20, (height - 44 - 16 - 22) / 6))

    title: {
        const s = dateLocale.toString(now, "MMMM yyyy");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }
    titleIcon: "calendar_month"

    Column {
        anchors.centerIn: parent

        Row {
            Repeater {
                // Monday first.
                model: [1, 2, 3, 4, 5, 6, 0]

                StyledText {
                    required property int modelData
                    width: root.cell
                    height: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: root.dateLocale.dayName(modelData, Locale.NarrowFormat)
                    role: "micro"
                    color: modelData === 0 || modelData === 6 ? Style.alpha(Colors.textOnSurfaceVariant, 0.7) : Colors.textOnSurfaceVariant
                }
            }
        }

        Grid {
            columns: 7

            Repeater {
                model: root.cells

                Item {
                    id: day
                    required property var modelData
                    width: root.cell
                    height: root.rowHeight

                    Shape {
                        anchors.centerIn: parent
                        width: Math.min(30, root.rowHeight)
                        height: width
                        visible: day.modelData.isToday
                        shape: "Cookie9Sided"
                        color: Colors.primary
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: day.modelData.day
                        role: "body"
                        font.features: ({ "tnum": 1 })
                        weight: day.modelData.isToday ? 750 : 500
                        color: day.modelData.isToday ? Colors.textOnPrimary : Colors.textOnSurface
                        opacity: day.modelData.inMonth ? 1 : 0.32
                    }
                }
            }
        }
    }
}
