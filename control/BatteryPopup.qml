import QtQuick
import qs.common
import qs.services

// The battery popup's content (in BarPopupCard, a click on the bar's
// battery), laid out like the macOS battery menu and its health page:
//
//      Battery                                 87%
//      On battery · 9.1 W · about 5 h 10 min left
//      ╭──────────────────────────────────────╮ 100%
//      │      ╱‾‾‾‾‾╲___                       │  50%
//      │_____╱          ‾‾‾‾╲____             │   0%
//      ╰──────────────────────────────────────╯
//      18:00      00:00      06:00      12:00
//      Last 24 hours        ━ On battery ━ Plugged in
//      Health                              Normal
//      Maximum capacity                      97%
//      Holds now / When new        57.4 / 59.2 Wh
//      Wear                                   3%
//      Charge cycles                         112
//      Battery settings…
//
// Everything comes from services/BatteryHealth.qml (read while this is open).
Column {
    id: root

    Component.onCompleted: BatteryHealth.use(true)
    Component.onDestruction: BatteryHealth.use(false)

    // The graph's "now" moves on while it's open.
    property real now: Date.now() / 1000
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.now = Date.now() / 1000
    }
    Connections {
        target: BatteryHealth
        function onHistoryAtChanged() { root.now = Date.now() / 1000; }
    }

    // ---- Battery                                        87% ----
    Item {
        width: parent.width
        height: 26

        StyledText {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "Battery"
            role: "title"
        }
        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: BatteryHealth.percent + "%"
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }
    }
    StyledText {
        x: 6
        width: parent.width - 12
        bottomPadding: 10
        text: BatteryHealth.stateText
        role: "caption"
        color: Colors.textOnSurfaceVariant
        elide: Text.ElideRight
    }

    // ---- The last hours ----------------------------------------------------------
    BatteryGraph {
        x: 6
        width: parent.width - 12
        height: 112
        points: BatteryHealth.history
        hours: Style.batteryGraphHours
        now: root.now
        nowValue: BatteryHealth.history.length > 0 ? BatteryHealth.percent : -1
        nowPlugged: BatteryHealth.chargeState !== "discharging"
        use24h: Style.clock24h
    }
    Item {
        width: parent.width
        height: 24

        StyledText {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            text: BatteryHealth.historyError !== "" && BatteryHealth.history.length === 0
                ? "No history: " + BatteryHealth.historyError
                : "Last " + Style.batteryGraphHours + " hours"
            role: "caption"
            color: Colors.textOnSurfaceVariant
            width: parent.width - legend.width - 18
            elide: Text.ElideRight
        }
        Row {
            id: legend
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Key { color: Colors.primary; text: "On battery" }
            Key { color: Colors.tertiary; text: "Plugged in" }
        }
    }

    // ---- Health -------------------------------------------------------------------
    Rule {}
    Item {
        width: parent.width
        height: 28
        visible: BatteryHealth.hasHealth || BatteryHealth.healthKnown

        StyledText {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "Health"
            role: "label"
            color: Colors.textOnSurfaceVariant
        }
        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: BatteryHealth.hasHealth ? BatteryHealth.condition : "Not reported"
            weight: 650
            color: BatteryHealth.condition === "Worn" ? Colors.error : Colors.textOnSurface
        }
    }
    Line {
        visible: BatteryHealth.hasHealth
        label: "Maximum capacity"
        value: BatteryHealth.healthText
    }
    Line {
        visible: BatteryHealth.hasHealth
        label: "Holds now / when new"
        value: BatteryHealth.fullText.replace(/ (Wh|mAh)$/, "") + " / " + BatteryHealth.designText
    }
    Line {
        visible: BatteryHealth.hasHealth
        label: "Wear"
        value: BatteryHealth.wearText
    }
    Line {
        visible: BatteryHealth.cycles > 0
        label: "Charge cycles"
        value: String(BatteryHealth.cycles)
    }

    // ---- Battery settings… ------------------------------------------------------------
    Rule {}
    MouseArea {
        id: settingsRow
        width: parent.width
        height: 28
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            BarPopupState.close();
            SettingsState.show("power");
        }

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Colors.textOnSurface
            opacity: settingsRow.pressed ? Style.pressTint : settingsRow.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        StyledText {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "Battery settings…"
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

    // "Wear                     3%"
    component Line: Item {
        property string label: ""
        property string value: ""
        width: root.width
        height: 24

        StyledText {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Colors.textOnSurfaceVariant
        }
        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            font.features: ({ "tnum": 1 })
        }
    }

    // A legend entry: a short line in the graph's color and its name.
    component Key: Row {
        property color color
        property string text
        spacing: 4

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 3
            radius: 1.5
            color: parent.color
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.text
            role: "caption"
            color: Colors.textOnSurfaceVariant
        }
    }
}
