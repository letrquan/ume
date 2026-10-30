import QtQuick
import qs.common
import qs.services

// The timers' page of the control center (services/Timers.qml), from the
// arrow of the Timer, Stopwatch or Alarm tile: three tabs.
//   Timer      the time left, Start / Pause / Cancel / +1 min, the presets,
//              any length typed (7, 1:30, 1h 20m)
//   Stopwatch  the time with tenths, Start / Pause, Lap / Reset, the laps
//   Alarms     each alarm (its switch; click to change the time, the days,
//              the label, or delete it), and a new one
// While one rings, Stop (and Snooze) sit at the top.
Column {
    id: root

    spacing: 12

    readonly property string tab: Timers.pageTab
    readonly property real cardRadius: Style.inner(Style.ccRadius, Style.ccPadding)

    // ---- Small parts -------------------------------------------------------------------
    // A rounded button: tinted, or filled with the accent (`strong`).
    component Pill: MouseArea {
        id: pill
        property string text: ""
        property string icon: ""
        property bool strong: false
        property bool on: true
        implicitWidth: pillRow.implicitWidth + 28
        implicitHeight: 38
        hoverEnabled: true
        enabled: on
        cursorShape: Qt.PointingHandCursor
        opacity: on ? 1 : 0.4

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: pill.strong ? Colors.primary : Style.alpha(Colors.textOnSurface, 0.08)
            scale: pill.pressed ? 0.96 : 1
            Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial } }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: pill.strong ? Colors.textOnPrimary : Colors.textOnSurface
                opacity: pill.pressed ? Style.pressTint : pill.containsMouse ? Style.hoverTint : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }
        }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.icon !== ""
                name: pill.icon
                size: 18
                color: pill.strong ? Colors.textOnPrimary : Colors.textOnSurface
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.text !== ""
                text: pill.text
                weight: 650
                color: pill.strong ? Colors.textOnPrimary : Colors.textOnSurface
            }
        }
    }

    // A one-line field; Enter is `accepted`. displayText: an input
    // method's unfinished word counts too.
    component Field: Rectangle {
        id: field
        property alias input: input
        property string hint: ""
        readonly property string value: input.displayText
        signal accepted()
        implicitHeight: 38
        radius: height / 2
        color: Style.alpha(Colors.textOnSurface, 0.08)
        border.width: 1
        border.color: input.activeFocus ? Colors.primary : "transparent"

        TextInput {
            id: input
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            color: Colors.textOnSurface
            selectionColor: Style.alpha(Colors.primary, 0.4)
            font.family: Style.font
            font.pixelSize: Style.textSize("body")
            clip: true
            onAccepted: {
                Qt.inputMethod.commit();
                field.accepted();
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: field.hint
                color: Colors.textOnSurfaceVariant
                visible: input.displayText === ""
            }
        }
    }

    PageHeader {
        width: parent.width
        title: root.tab === "stopwatch" ? "Stopwatch" : root.tab === "alarms" ? "Alarms" : "Timer"
    }

    // ---- Ringing -------------------------------------------------------------------
    Rectangle {
        width: parent.width
        height: ringColumn.implicitHeight + 24
        visible: Timers.ringing
        radius: root.cardRadius
        color: Style.alpha(Colors.primary, 0.18)

        Column {
            id: ringColumn
            x: 14
            y: 12
            width: parent.width - 28
            spacing: 10

            Row {
                spacing: 10
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: Timers.ringKind === "alarm" ? "alarm" : "timer"
                    size: 22
                    fill: 1
                    color: Colors.primary
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    StyledText { text: Timers.ringTitle; role: "title" }
                    StyledText { text: Timers.ringBody; role: "caption"; color: Colors.textOnSurfaceVariant }
                }
            }
            Row {
                spacing: 8
                Pill {
                    text: "Stop"
                    icon: "stop"
                    strong: true
                    onClicked: Timers.stopRing()
                }
                Pill {
                    visible: Timers.ringKind === "alarm"
                    text: "Snooze " + Style.timersSnoozeMinutes + " min"
                    icon: "snooze"
                    onClicked: Timers.snooze()
                }
                Pill {
                    visible: Timers.ringKind === "timer"
                    text: "Again"
                    icon: "replay"
                    onClicked: {
                        const length = Timers.lastLength;
                        Timers.stopRing();
                        Timers.startTimer(length);
                    }
                }
            }
        }
    }

    // ---- Tabs ----------------------------------------------------------------------
    Item {
        id: tabs
        width: parent.width
        height: 36

        readonly property var list: [
            { id: "timer", label: "Timer" },
            { id: "stopwatch", label: "Stopwatch" },
            { id: "alarms", label: "Alarms" }
        ]
        readonly property real cell: width / list.length

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Style.alpha(Colors.textOnSurface, 0.08)
        }
        Rectangle {
            x: tabs.cell * Math.max(0, tabs.list.findIndex(t => t.id === root.tab)) + 3
            y: 3
            width: tabs.cell - 6
            height: parent.height - 6
            radius: height / 2
            color: Colors.primary
            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        }
        Row {
            anchors.fill: parent
            Repeater {
                model: tabs.list
                MouseArea {
                    required property var modelData
                    width: tabs.cell
                    height: tabs.height
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Timers.pageTab = modelData.id
                    StyledText {
                        anchors.centerIn: parent
                        text: parent.modelData.label
                        weight: 650
                        color: root.tab === parent.modelData.id ? Colors.textOnPrimary : Colors.textOnSurface
                    }
                }
            }
        }
    }

    // ---- Timer ---------------------------------------------------------------------
    Column {
        width: parent.width
        spacing: 12
        visible: root.tab === "timer"

        // The time left (or the length it would start with), and how far.
        Item {
            width: parent.width
            height: 86

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4
                text: Timers.timerState === "idle" ? Timers.clockText(Timers.lastLength / 1000) : Timers.timerText
                font.pixelSize: 52
                font.features: ({ "tnum": 1 })
                weight: 650
                opacity: Timers.timerState === "paused" ? 0.55 : Timers.timerState === "idle" ? 0.7 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.normal } }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 6
                radius: 3
                color: Style.alpha(Colors.textOnSurface, 0.1)
                Rectangle {
                    width: parent.width * Math.min(1, Timers.timerProgress)
                    height: parent.height
                    radius: 3
                    color: Colors.primary
                    Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Pill {
                text: "Cancel"
                on: Timers.timerState !== "idle"
                onClicked: Timers.cancelTimer()
            }
            Pill {
                strong: true
                icon: Timers.timerState === "running" ? "pause" : "play_arrow"
                text: Timers.timerState === "running" ? "Pause" : Timers.timerState === "paused" ? "Go on" : "Start"
                onClicked: Timers.toggleTimer()
            }
            Pill {
                text: "+1 min"
                onClicked: Timers.addMinute()
            }
        }

        // The presets: click starts one right away.
        Grid {
            width: parent.width
            columns: 3
            spacing: 8
            Repeater {
                model: Timers.presets
                Pill {
                    required property int modelData
                    width: (parent.width - 16) / 3
                    text: modelData + " min"
                    onClicked: Timers.startMinutes(modelData)
                }
            }
        }

        Row {
            width: parent.width
            spacing: 8
            Field {
                id: custom
                width: parent.width - startCustom.width - 8
                hint: "Any length: 7, 1:30, 1h 20m"
                onAccepted: startCustom.clicked(null)
            }
            Pill {
                id: startCustom
                text: "Start"
                on: Timers.parseLength(custom.value) > 0
                onClicked: {
                    if (Timers.startTimer(Timers.parseLength(custom.value)))
                        custom.input.text = "";
                }
            }
        }
    }

    // ---- Stopwatch -------------------------------------------------------------------
    Column {
        width: parent.width
        spacing: 12
        visible: root.tab === "stopwatch"

        // Tenths while it shows and runs (only here: the service counts seconds).
        property real fine: Timers.now()
        Timer {
            interval: 100
            repeat: true
            running: root.tab === "stopwatch" && Timers.swRunning && root.visible
            onTriggered: parent.fine = Timers.now()
        }
        readonly property real elapsed: Timers.swElapsed(Timers.swRunning ? fine : 0)

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Timers.clockText(parent.elapsed / 1000) + "." + Math.floor(parent.elapsed % 1000 / 100)
            font.pixelSize: 52
            font.features: ({ "tnum": 1 })
            weight: 650
            opacity: Timers.swStarted && !Timers.swRunning ? 0.55 : 1
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Pill {
                text: Timers.swRunning ? "Lap" : "Reset"
                icon: Timers.swRunning ? "flag" : "restart_alt"
                on: Timers.swStarted
                onClicked: Timers.swRunning ? Timers.lap() : Timers.resetStopwatch()
            }
            Pill {
                strong: true
                icon: Timers.swRunning ? "pause" : "play_arrow"
                text: Timers.swRunning ? "Pause" : Timers.swStarted ? "Go on" : "Start"
                onClicked: Timers.toggleStopwatch()
            }
        }

        // Laps, newest first: its own time, and the total then.
        Flickable {
            width: parent.width
            height: Math.min(lapColumn.implicitHeight, 200)
            visible: Timers.swLaps.length > 0
            contentHeight: lapColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: lapColumn
                width: parent.width
                Repeater {
                    model: Timers.swLaps.length
                    Item {
                        required property int index
                        readonly property int n: Timers.swLaps.length - index
                        readonly property real total: Timers.swLaps[n - 1]
                        readonly property real own: total - (n > 1 ? Timers.swLaps[n - 2] : 0)
                        width: lapColumn.width
                        height: 30
                        StyledText { x: 4; anchors.verticalCenter: parent.verticalCenter; text: "Lap " + parent.n; color: Colors.textOnSurfaceVariant }
                        StyledText {
                            anchors.centerIn: parent
                            text: Timers.clockText(parent.own / 1000) + "." + Math.floor(parent.own % 1000 / 100)
                            font.features: ({ "tnum": 1 })
                            weight: 650
                        }
                        StyledText {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: Timers.clockText(parent.total / 1000) + "." + Math.floor(parent.total % 1000 / 100)
                            font.features: ({ "tnum": 1 })
                            color: Colors.textOnSurfaceVariant
                        }
                    }
                }
            }
        }
    }

    // ---- Alarms ----------------------------------------------------------------------
    Column {
        id: alarmTab
        width: parent.width
        spacing: 8
        visible: root.tab === "alarms"

        property string editing: ""          // the alarm open for changes ("new": a new one)

        StyledText {
            width: parent.width
            visible: Timers.alarms.length === 0 && alarmTab.editing === ""
            topPadding: 6
            bottomPadding: 6
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "No alarms. The laptop can't wake itself: an alarm rings while it's awake, and says it was missed if it slept through."
            role: "caption"
            color: Colors.textOnSurfaceVariant
        }

        Repeater {
            model: Timers.alarms

            Rectangle {
                id: alarmRow
                required property var modelData
                readonly property bool open: alarmTab.editing === modelData.id
                width: alarmTab.width
                height: rowTop.height + (open ? editor.implicitHeight + 10 : 0)
                radius: root.cardRadius
                color: Style.alpha(Colors.textOnSurface, 0.06)
                clip: true
                Behavior on height { NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

                MouseArea {
                    id: rowTop
                    width: parent.width
                    height: 60
                    cursorShape: Qt.PointingHandCursor
                    onClicked: alarmTab.editing = alarmRow.open ? "" : alarmRow.modelData.id

                    Column {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        StyledText {
                            text: alarmRow.modelData.time
                            font.pixelSize: 26
                            font.features: ({ "tnum": 1 })
                            weight: 650
                            opacity: alarmRow.modelData.on ? 1 : 0.5
                        }
                        StyledText {
                            text: (alarmRow.modelData.label !== "" ? alarmRow.modelData.label + " · " : "") + Timers.daysText(alarmRow.modelData.days)
                                  + (alarmRow.modelData.snooze > 0 ? " · snoozed till " + Qt.formatTime(new Date(alarmRow.modelData.snooze), "HH:mm") : "")
                            role: "caption"
                            color: Colors.textOnSurfaceVariant
                        }
                    }
                    Toggle {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        checked: alarmRow.modelData.on
                        onFlipped: Timers.toggleAlarm(alarmRow.modelData.id)
                    }
                }

                AlarmEditor {
                    id: editor
                    y: rowTop.height
                    x: 14
                    width: parent.width - 28
                    visible: alarmRow.open
                    alarm: alarmRow.modelData
                    onDone: alarmTab.editing = ""
                }
            }
        }

        // A new one.
        Rectangle {
            width: parent.width
            height: alarmTab.editing === "new" ? fresh.implicitHeight + 24 : 0
            visible: height > 0
            radius: root.cardRadius
            color: Style.alpha(Colors.textOnSurface, 0.06)
            clip: true

            AlarmEditor {
                id: fresh
                x: 14
                y: 12
                width: parent.width - 28
                alarm: null
                onDone: alarmTab.editing = ""
            }
        }

        Pill {
            visible: alarmTab.editing !== "new"
            icon: "add"
            text: "New alarm"
            onClicked: alarmTab.editing = "new"
        }
    }

    // The time (steps of an hour / 5 minutes, or typed), the days, the
    // label; Save, and Delete for one that exists.
    component AlarmEditor: Column {
        id: ed
        property var alarm: null
        signal done()

        spacing: 10

        property int hour: 7
        property int min: 0
        property var days: []
        function reset() {
            const t = (alarm?.time ?? "07:00").split(":").map(Number);
            hour = t[0];
            min = t[1];
            days = (alarm?.days ?? []).slice();
            label.input.text = alarm?.label ?? "";
        }
        onAlarmChanged: reset()
        onVisibleChanged: if (visible) reset()
        Component.onCompleted: reset()
        readonly property string time: String(hour).padStart(2, "0") + ":" + String(min).padStart(2, "0")

        // HH : MM, each with − and +, or scroll on it.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Repeater {
                model: [{ part: "h" }, { part: "m" }]
                Row {
                    required property var modelData
                    required property int index
                    spacing: 4
                    readonly property bool hours: modelData.part === "h"
                    function step(by) {
                        if (hours)
                            ed.hour = (ed.hour + by + 24) % 24;
                        else
                            ed.min = (Math.round(ed.min / 5) * 5 + by * 5 + 60) % 60;
                    }
                    StyledText {
                        visible: index === 1
                        anchors.verticalCenter: parent.verticalCenter
                        text: ":"
                        font.pixelSize: 34
                        weight: 650
                    }
                    Pill { anchors.verticalCenter: parent.verticalCenter; icon: "remove"; implicitWidth: 38; onClicked: parent.step(-1) }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 54
                        horizontalAlignment: Text.AlignHCenter
                        text: String(parent.hours ? ed.hour : ed.min).padStart(2, "0")
                        font.pixelSize: 34
                        font.features: ({ "tnum": 1 })
                        weight: 650
                        WheelHandler {
                            onWheel: event => parent.parent.step(event.angleDelta.y > 0 ? 1 : -1)
                        }
                    }
                    Pill { anchors.verticalCenter: parent.verticalCenter; icon: "add"; implicitWidth: 38; onClicked: parent.step(1) }
                }
            }
        }

        // The days: none = once.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Repeater {
                model: 7
                MouseArea {
                    required property int index
                    // Monday first.
                    readonly property int day: (index + 1) % 7
                    readonly property bool chosen: ed.days.includes(day)
                    width: 36
                    height: 36
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ed.days = chosen ? ed.days.filter(d => d !== day) : ed.days.concat([day])
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: parent.chosen ? Colors.primary : Style.alpha(Colors.textOnSurface, 0.08)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: Timers.dayLetters[parent.day]
                        weight: 650
                        color: parent.chosen ? Colors.textOnPrimary : Colors.textOnSurface
                    }
                }
            }
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Timers.daysText(ed.days)
            role: "caption"
            color: Colors.textOnSurfaceVariant
        }

        Field {
            id: label
            width: parent.width
            hint: "Label (optional)"
            onAccepted: save.clicked(null)
        }

        Row {
            spacing: 8
            Pill {
                id: save
                strong: true
                text: ed.alarm ? "Save" : "Add"
                onClicked: {
                    Qt.inputMethod.commit();
                    if (ed.alarm)
                        Timers.updateAlarm(ed.alarm.id, { time: ed.time, days: ed.days, label: label.value, on: true });
                    else
                        Timers.addAlarm(ed.time, ed.days, label.value);
                    ed.done();
                }
            }
            Pill {
                text: "Cancel"
                onClicked: ed.done()
            }
            Pill {
                visible: ed.alarm !== null
                icon: "delete"
                text: "Delete"
                onClicked: {
                    Timers.removeAlarm(ed.alarm.id);
                    ed.done();
                }
            }
        }
    }
}
