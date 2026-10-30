import QtQuick
import qs.common
import qs.services

// The screen time popup's content (in BarPopupCard, a click on the bar's
// "Screen time"), like the iPhone's Screen Time:
//
//      Screen time                          3 h 12 m
//      Today
//        ▆                                   ▇
//      ▃ █ ▅  ▂  ▆  ▄  █        (tap a day)
//      Mon Tue Wed Thu Fri Sat Today
//      [icon] Foot        ━━━━━━━━━━━━   1 h 20 m
//      [icon] Brave       ━━━━━━━          50 m
//      …
//      Break reminders                        (●)
//      Every 50 min · next in 23 min
//      Take a break now
//      Screen time settings…
//
// Everything comes from services/ScreenTime.qml and services/Breaks.qml.
Column {
    id: root

    // Now, for today's live numbers: once every 30 s while open.
    property real now: Date.now()
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }
    readonly property int revision: ScreenTime.revision
    readonly property var week: revision >= 0 ? ScreenTime.week(now) : []
    readonly property string todayKey: ScreenTime.dayKey(now)
    // The day shown below the chart (a tap on a bar).
    property string picked: ""
    readonly property string dayKey: picked !== "" ? picked : todayKey
    readonly property var day: week.find(d => d.key === dayKey) ?? week[week.length - 1] ?? { key: todayKey, label: "Today", seconds: 0 }
    readonly property var apps: revision >= 0 ? ScreenTime.appsOn(dayKey, now) : []
    readonly property int shownApps: 6
    readonly property real otherSeconds: apps.slice(shownApps).reduce((s, a) => s + a.seconds, 0)
    readonly property real maxApp: apps.length > 0 ? apps[0].seconds : 1

    function dayTitle(d) {
        return d.key === todayKey ? "Today" : d.label === "Today" ? d.label : longDay(d.key);
    }
    function longDay(key) {
        const [y, m, dd] = key.split("-").map(Number);
        return Qt.formatDate(new Date(y, m - 1, dd), "dddd d MMMM");
    }

    // ---- Screen time                               3 h 12 m ----
    Item {
        width: parent.width
        height: 26

        StyledText {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "Screen time"
            role: "title"
        }
        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: ScreenTime.durationText(root.day.seconds, false)
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }
    }
    StyledText {
        x: 6
        width: parent.width - 12
        bottomPadding: 8
        text: !ScreenTime.enabled ? "Not counting (Settings → Screen time)"
            : root.dayTitle(root.day) + (root.dayKey === root.todayKey && ScreenTime.current !== ""
                ? " · now " + ScreenTime.appName(ScreenTime.current) : "")
        role: "caption"
        color: Colors.textOnSurfaceVariant
        elide: Text.ElideRight
    }

    // ---- The last 7 days ------------------------------------------------------------
    Item {
        id: chart
        x: 6
        width: parent.width - 12
        height: 104

        readonly property real peak: Math.max(3600, ...root.week.map(d => d.seconds))
        readonly property real slot: width / 7

        // A faint line at the average of the days with any time.
        readonly property var counted: root.week.filter(d => d.seconds >= 60)
        readonly property real average: counted.length > 0 ? counted.reduce((s, d) => s + d.seconds, 0) / counted.length : 0
        Rectangle {
            visible: chart.average > 0
            x: 0
            width: parent.width
            height: 1
            y: 84 - 78 * chart.average / chart.peak
            color: Style.alpha(Colors.textOnSurface, 0.18)
        }

        Repeater {
            model: root.week

            MouseArea {
                id: dayArea
                required property var modelData
                required property int index
                readonly property bool isPicked: modelData.key === root.dayKey
                x: index * chart.slot
                width: chart.slot
                height: chart.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked = modelData.key === root.todayKey ? "" : modelData.key

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(22, chart.slot - 10)
                    radius: 5
                    y: 84 - height
                    height: Math.max(4, 78 * dayArea.modelData.seconds / chart.peak)
                    color: dayArea.isPicked ? Colors.primary : Style.alpha(Colors.primary, dayArea.containsMouse ? 0.55 : 0.32)
                    Behavior on height { NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 88
                    text: dayArea.modelData.label === "Today" ? "Today" : dayArea.modelData.label
                    role: "micro"
                    weight: dayArea.isPicked ? 650 : Style.textWeight("micro")
                    color: dayArea.isPicked ? Colors.textOnSurface : Colors.textOnSurfaceVariant
                }
            }
        }
    }
    StyledText {
        x: 6
        width: parent.width - 12
        topPadding: 2
        bottomPadding: 4
        visible: chart.average > 0
        text: "Daily average " + ScreenTime.durationText(chart.average, false)
        role: "caption"
        color: Colors.textOnSurfaceVariant
    }

    // ---- Per app --------------------------------------------------------------------
    Rule {}
    StyledText {
        x: 6
        visible: root.apps.length === 0
        topPadding: 4
        bottomPadding: 6
        text: root.dayKey === root.todayKey ? "Nothing yet today" : "Nothing that day"
        color: Colors.textOnSurfaceVariant
    }
    Repeater {
        model: root.apps.slice(0, root.shownApps)

        AppRow {
            required property var modelData
            appId: modelData.appId
            seconds: modelData.seconds
        }
    }
    AppRow {
        visible: root.otherSeconds >= 60
        appId: ""
        seconds: root.otherSeconds
    }

    // ---- Break reminders --------------------------------------------------------------
    Rule {}
    Item {
        width: parent.width
        height: 40

        Column {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - breakToggle.width - 18

            StyledText {
                text: "Break reminders"
            }
            StyledText {
                width: parent.width
                text: Breaks.enabled && Breaks.phase === "work" && !Breaks.away && !Breaks.waiting
                    ? "Every " + Breaks.minutesText(Breaks.afterMs) + " · next in " + Breaks.minutesText(Math.max(0, Breaks.nextAt - root.now))
                    : Breaks.detail
                role: "caption"
                color: Colors.textOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
        Toggle {
            id: breakToggle
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            checked: Breaks.enabled
            onFlipped: Breaks.setOn(!Breaks.enabled)
        }
    }
    ActionRow {
        visible: Breaks.phase === "work"
        text: "Take a break now"
        onClicked: {
            BarPopupState.close();
            Breaks.takeBreak();
        }
    }
    ActionRow {
        text: "Screen time settings…"
        onClicked: {
            BarPopupState.close();
            SettingsState.show("usage");
        }
    }

    // [icon] Name          ━━━━━━━━━━     1 h 20 m
    component AppRow: Item {
        id: row
        property string appId: ""
        property real seconds: 0
        width: root.width
        height: 34

        AppIcon {
            id: icon
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            visible: row.appId !== ""
            implicitSize: 22
            source: row.appId !== "" ? ScreenTime.appIcon(row.appId) : ""
            name: row.appId !== "" ? ScreenTime.appName(row.appId) : ""
        }
        Icon {
            x: 6
            width: 22
            anchors.verticalCenter: parent.verticalCenter
            visible: row.appId === ""
            name: "more_horiz"
            size: 18
            color: Colors.textOnSurfaceVariant
        }
        StyledText {
            id: nameText
            x: 38
            y: 3
            width: parent.width - x - timeText.implicitWidth - 14
            text: row.appId === "" ? "Other apps" : ScreenTime.appName(row.appId)
            elide: Text.ElideRight
        }
        Rectangle {
            x: 38
            y: 23
            height: 4
            radius: 2
            width: Math.max(4, (parent.width - x - 6) * Math.min(1, row.seconds / root.maxApp))
            color: row.appId === "" ? Style.alpha(Colors.textOnSurface, 0.25) : Colors.primary
            opacity: 0.85
            Behavior on width { NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        }
        StyledText {
            id: timeText
            anchors.right: parent.right
            anchors.rightMargin: 6
            y: 3
            text: ScreenTime.durationText(row.seconds, false)
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }
    }

    // A row you click, like "Battery settings…".
    component ActionRow: MouseArea {
        id: action
        property string text: ""
        width: root.width
        height: 28
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Colors.textOnSurface
            opacity: action.pressed ? Style.pressTint : action.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        StyledText {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            text: action.text
        }
    }

    // A thin line between the parts, like macOS menus.
    component Rule: Item {
        width: root.width
        height: 13

        Rectangle {
            x: 6
            width: parent.width - 12
            height: 1
            anchors.verticalCenter: parent.verticalCenter
            color: Style.alpha(Colors.textOnSurface, 0.1)
        }
    }
}
