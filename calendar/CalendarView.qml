import QtQuick
import Quickshell
import qs.common
import qs.services

// The calendar. Like the launcher it grows out of the middle island
// (MorphCard), here into a month calendar with your events (when there are
// calendar addresses, Settings → Calendar & weather) and the weather under it.
//
//      ╭──────────────────────────────────────╮
//      │  15   Wednesday            ‹ Today › │
//      │       October 2026                   │
//      │  M  T  W  T  F  S  S                 │
//      │  …  …  (15) …                        │  ← today on a cookie, • = events
//      ├──────────────────────────────────────┤
//      │ ▍ Dentist                10:00 – 11:00 │  ← the day you clicked (today)
//      ├──────────────────────────────────────┤
//      │ (☁) 31°  Partly cloudy   H 33° L 25° │
//      │  14:00  15:00  16:00  17:00  18:00   │
//      ╰──────────────────────────────────────╯
//
// ←/→ (or scroll) changes the month, T / Home goes back to today, Esc
// closes. Plain QtQuick (plus Weather), so it can be previewed.
Item {
    id: root

    // Width of the middle island right now: where we start and end.
    property real startWidth: 200
    property bool open: false

    // While true the bar hides the real middle island.
    readonly property bool covering: morph.covering
    // Fully back in the island: the window can go.
    readonly property bool settled: morph.settled
    readonly property alias cardItem: morph.card

    signal closeRequested()

    readonly property var dateLocale: Style.clockLocale !== "" ? Qt.locale(Style.clockLocale) : Qt.locale()
    readonly property date today: clock.date
    // The month shown, as months away from this one (0 = this month).
    property int offset: 0
    readonly property date month: new Date(today.getFullYear(), today.getMonth() + offset, 1)

    // The day whose events show (click a day; today when it opens).
    property date selected: new Date()

    // Six weeks, Monday first: { day, inMonth, isToday, date }.
    readonly property var cells: {
        const first = month;
        const lead = (first.getDay() + 6) % 7;    // Monday = 0
        const out = [];
        for (let i = 0; i < 42; i++) {
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

    function focusKeys() {
        keys.forceActiveFocus();
    }

    // Change the month: the grid leaves the other way and comes back in
    // from the side we're going to.
    property int direction: 1
    function go(by) {
        if (by === 0 || swap.running)
            return;
        direction = by > 0 ? 1 : -1;
        nextOffset = offset + by;
        swap.restart();
    }
    function goToday() {
        if (offset !== 0)
            go(-offset);
    }
    property int nextOffset: 0

    onOpenChanged: {
        if (open) {
            offset = 0;
            selected = today;
        }
    }

    // A click on a day: its events (a day of the month before or after: go there too).
    function select(d) {
        if (d.getMonth() !== month.getMonth())
            go(d.getFullYear() * 12 + d.getMonth() > month.getFullYear() * 12 + month.getMonth() ? 1 : -1);
        selected = d;
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: monthPane; property: "opacity"; to: 0; duration: 90; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
            NumberAnimation { target: slide; property: "x"; to: -root.direction * 18; duration: 90; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
        }
        ScriptAction {
            script: {
                root.offset = root.nextOffset;
                slide.x = root.direction * 26;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: monthPane; property: "opacity"; to: 1; duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            NumberAnimation { target: slide; property: "x"; to: 0; duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }
    }

    readonly property real pad: 16
    readonly property real cell: (Style.calendarWidth - pad * 2) / 7
    readonly property bool showWeather: Style.weatherEnabled && Weather.ready

    MorphCard {
        id: morph

        anchors.fill: parent
        fromX: (width - root.startWidth) / 2
        fromY: Style.islandTop
        fromWidth: root.startWidth
        toWidth: Style.calendarWidth
        toHeight: content.implicitHeight + root.pad * 2
        radius: Style.calendarRadius
        glassOpacity: Style.calendarOpacity
        open: root.open

        // Clicks on the card stay on the card; scrolling changes the month.
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => {
                const step = wheel.angleDelta.y || -wheel.angleDelta.x;
                if (step !== 0)
                    root.go(step > 0 ? -1 : 1);
            }
        }

        // Keys: ←/→ months, T/Home today, Esc close.
        Item {
            id: keys
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape)
                    root.closeRequested();
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_PageUp || event.key === Qt.Key_H)
                    root.go(-1);
                else if (event.key === Qt.Key_Right || event.key === Qt.Key_PageDown || event.key === Qt.Key_L)
                    root.go(1);
                else if (event.key === Qt.Key_T || event.key === Qt.Key_Home)
                    root.goToday();
                else
                    return;
                event.accepted = true;
            }
        }

        Column {
            id: content
            x: root.pad
            y: root.pad
            width: Style.calendarWidth - root.pad * 2
            spacing: 12

            // ---- Today, and the month shown ----------------------------------------
            Item {
                width: parent.width
                height: 52

                StyledText {
                    id: bigDay
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.today.getDate()
                    font.pixelSize: Style.calendarDaySize
                    weight: 750
                    font.features: ({ "tnum": 1 })
                    color: Colors.primary
                }

                Column {
                    anchors.left: bigDay.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    StyledText {
                        text: root.dateLocale.toString(root.today, "dddd")
                        role: "title"
                    }
                    StyledText {
                        text: root.dateLocale.toString(root.month, "MMMM yyyy")
                        role: "caption"
                        color: root.offset === 0 ? Colors.textOnSurfaceVariant : Colors.primary
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Clickable {
                        onClicked: root.go(-1)
                        Icon { name: "chevron_left"; size: 20 }
                    }

                    // Back to this month (only when away from it).
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.offset !== 0 ? todayChip.width : 0
                        height: todayChip.height
                        clip: true
                        Behavior on width {
                            NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
                        }

                        Clickable {
                            id: todayChip
                            implicitHeight: 28
                            padding: 10
                            onClicked: root.goToday()

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Today"
                                role: "label"
                                color: Colors.primary
                            }
                        }
                    }

                    Clickable {
                        onClicked: root.go(1)
                        Icon { name: "chevron_right"; size: 20 }
                    }
                }
            }

            // ---- The month ------------------------------------------------------------
            Item {
                id: monthPane
                width: parent.width
                height: names.height + grid.height
                clip: true
                transform: Translate { id: slide }

                Row {
                    id: names
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
                    id: grid
                    y: names.height
                    columns: 7

                    Repeater {
                        model: root.cells

                        Item {
                            id: day
                            required property var modelData
                            width: root.cell
                            height: 38

                            readonly property bool isSelected: Events.enabled && !modelData.isToday
                                && modelData.date.toDateString() === root.selected.toDateString()
                            readonly property int events: Events.enabled && Events.revision >= 0 ? Events.count(modelData.date) : 0

                            Shape {
                                anchors.centerIn: parent
                                width: 34
                                height: 34
                                visible: day.modelData.isToday
                                shape: "Cookie9Sided"
                                color: Colors.primary
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 32
                                height: 32
                                radius: 16
                                visible: !day.modelData.isToday
                                color: Colors.textOnSurface
                                opacity: hover.hovered && day.modelData.inMonth ? Style.hoverTint : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            }
                            // The chosen day (not today: that one is the cookie).
                            Rectangle {
                                anchors.centerIn: parent
                                width: 32
                                height: 32
                                radius: 16
                                visible: day.isSelected
                                color: "transparent"
                                border.width: 1.5
                                border.color: Colors.primary
                            }
                            HoverHandler {
                                id: hover
                            }
                            TapHandler {
                                enabled: Events.enabled
                                onTapped: root.select(day.modelData.date)
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
                            // Something on this day.
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: parent.height - 9
                                width: 4
                                height: 4
                                radius: 2
                                visible: day.events > 0
                                color: day.modelData.isToday ? Colors.textOnPrimary : Colors.primary
                                opacity: day.modelData.inMonth ? 1 : 0.4
                            }
                        }
                    }
                }
            }

            // ---- Your events on the chosen day -----------------------------------------
            Column {
                id: agenda
                width: parent.width
                visible: Events.enabled
                spacing: 4

                readonly property int maxRows: 4
                readonly property var list: Events.revision >= 0 ? Events.on(root.selected) : []
                readonly property bool isToday: root.selected.toDateString() === root.today.toDateString()
                // Nothing today: the next thing coming.
                readonly property var next: isToday && list.length === 0 && Events.revision >= 0
                    ? Events.nextAfter(root.today.getTime(), true) : null

                function sameDay(ms, d) {
                    return new Date(ms).toDateString() === d.toDateString();
                }
                // "10:00 – 11:00", "All day", "… – 01:00" (began the day before).
                function when(o) {
                    if (o.allDay)
                        return "All day";
                    const from = sameDay(o.start, root.selected) ? Events.time(o.start) : "…";
                    if (o.end <= o.start)
                        return from;
                    return from + " – " + (sameDay(o.end - 1, root.selected) ? Events.time(o.end) : "…");
                }
                function nextText(o) {
                    const d = new Date(o.start);
                    const inAWeek = o.start - root.today.getTime() < 6 * 86400000;
                    return (inAWeek ? root.dateLocale.toString(d, "ddd") : root.dateLocale.toString(d, "d MMM"))
                        + (o.allDay ? "" : " " + Events.time(o.start)) + "  " + o.title;
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Style.alpha(Colors.textOnSurface, 0.1)
                }

                Item {
                    width: parent.width
                    height: 22

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: agenda.isToday ? "Today" : root.dateLocale.toString(root.selected, "dddd d MMMM")
                        role: "label"
                        color: Colors.textOnSurfaceVariant
                    }
                    // Can't reach the calendar: what's shown is the saved copy.
                    Icon {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Events.status !== ""
                        name: "cloud_off"
                        size: 15
                        color: Colors.textOnSurfaceVariant
                    }
                }

                Repeater {
                    model: agenda.list.slice(0, agenda.maxRows)

                    Item {
                        id: event
                        required property var modelData
                        width: agenda.width
                        height: event.modelData.location !== "" ? 38 : 26

                        Rectangle {
                            id: bar
                            x: 1
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: parent.height - 6
                            radius: 1.5
                            color: Events.colorOf(event.modelData.cal)
                        }
                        StyledText {
                            id: title
                            anchors.left: bar.right
                            anchors.leftMargin: 10
                            anchors.right: whenText.left
                            anchors.rightMargin: 10
                            y: 3
                            text: event.modelData.title
                            role: "body"
                            weight: 600
                            elide: Text.ElideRight
                        }
                        StyledText {
                            id: whenText
                            anchors.right: parent.right
                            anchors.baseline: title.baseline
                            text: agenda.when(event.modelData)
                            role: "caption"
                            font.features: ({ "tnum": 1 })
                            color: Colors.textOnSurfaceVariant
                        }
                        StyledText {
                            anchors.left: title.left
                            anchors.right: parent.right
                            anchors.top: title.bottom
                            visible: event.modelData.location !== ""
                            text: event.modelData.location
                            role: "caption"
                            color: Colors.textOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                }

                StyledText {
                    visible: agenda.list.length > agenda.maxRows
                    leftPadding: 14
                    text: "+" + (agenda.list.length - agenda.maxRows) + " more"
                    role: "caption"
                    color: Colors.textOnSurfaceVariant
                }
                StyledText {
                    width: parent.width
                    visible: agenda.list.length === 0
                    text: agenda.isToday
                        ? (agenda.next ? "Nothing today  ·  Next: " + agenda.nextText(agenda.next) : "Nothing today")
                        : "Nothing on this day"
                    role: "caption"
                    color: Colors.textOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            // ---- The weather ----------------------------------------------------------
            Rectangle {
                width: parent.width
                height: 1
                visible: root.showWeather
                color: Style.alpha(Colors.textOnSurface, 0.1)
            }

            Item {
                width: parent.width
                height: 48
                visible: root.showWeather

                Item {
                    id: badge
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42
                    height: 42

                    Shape {
                        anchors.fill: parent
                        shape: "Cookie12Sided"
                        color: Colors.secondaryContainer
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: Weather.icon(Weather.code, Weather.isDay)
                        size: 22
                        color: Colors.textOnSecondaryContainer
                    }
                }

                StyledText {
                    id: temp
                    anchors.left: badge.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(Weather.temperature) + "°"
                    role: "display"
                    font.features: ({ "tnum": 1 })
                }

                Column {
                    anchors.left: temp.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    StyledText {
                        width: parent.width
                        text: Weather.words(Weather.code) + "  ·  " + Style.weatherCity
                        role: "label"
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        // Old data (offline): say how old.
                        readonly property string age: Weather.ageMinutes < 90 ? ""
                            : "  ·  " + (Weather.ageMinutes < 48 * 60 ? Math.round(Weather.ageMinutes / 60) + "h ago" : Math.round(Weather.ageMinutes / 1440) + "d ago")
                        text: "H " + Math.round(Weather.high) + "°  L " + Math.round(Weather.low) + "°" + age
                        role: "caption"
                        color: Colors.textOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            // The next few hours.
            Row {
                width: parent.width
                visible: root.showWeather && hours.count > 0

                Repeater {
                    id: hours
                    model: Weather.nextHours(Style.weatherHours)

                    Column {
                        required property var modelData
                        width: (Style.calendarWidth - root.pad * 2) / Math.max(1, hours.count)
                        spacing: 3

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: parent.modelData.hour
                            role: "caption"
                            color: Colors.textOnSurfaceVariant
                        }
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: Weather.icon(parent.modelData.code, parent.modelData.isDay)
                            size: 18
                            color: Colors.textOnSurface
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(parent.modelData.temp) + "°"
                            role: "label"
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }
}
