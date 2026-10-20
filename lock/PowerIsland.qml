import QtQuick
import Quickshell.Services.UPower
import qs.common

// The lock screen's right island, like the bar's: the battery and ⏻.
// ⏻ opens the island into Sleep · Restart · Shut down (two steps on
// purpose, so a stray click can't turn the laptop off); it closes again by
// itself after a few seconds.
LockIsland {
    id: root

    property bool open: false
    signal action(string name)    // "suspend" | "reboot" | "poweroff"

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isLaptopBattery ?? false
    readonly property real percent: hasBattery ? (battery.percentage ?? 0) * 100 : 0
    readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging
    readonly property bool low: percent <= Style.batteryLow && !charging

    Timer {
        running: root.open
        interval: 6000
        onTriggered: root.open = false
    }

    // Battery
    Item {
        visible: root.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: batteryRow.implicitWidth + 12
        implicitHeight: Style.itemHeight

        Row {
            id: batteryRow
            anchors.centerIn: parent
            spacing: 3

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.charging ? "battery_charging_full"
                    : root.percent >= 95 ? "battery_full"
                    : "battery_" + Math.max(0, Math.min(6, Math.floor(root.percent / 100 * 7))) + "_bar"
                rotation: 90
                color: root.low ? Colors.error : root.charging ? Colors.tertiary : Colors.textOnSurface
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(root.percent) + "%"
                color: root.low ? Colors.error : Colors.textOnSurface
                font.features: ({ "tnum": 1 })
            }
        }
    }

    // Sleep · Restart · Shut down, sliding open.
    Repeater {
        model: [
            { name: "suspend", icon: "bedtime", label: "Sleep" },
            { name: "reboot", icon: "restart_alt", label: "Restart" },
            { name: "poweroff", icon: "power_settings_new", label: "Shut down" }
        ]

        Item {
            id: entry
            required property var modelData
            required property int index
            readonly property bool danger: modelData.name === "poweroff"

            anchors.verticalCenter: parent.verticalCenter
            visible: implicitWidth > 0.5
            implicitWidth: root.open ? label.implicitWidth + 24 : 0
            implicitHeight: Style.itemHeight
            opacity: root.open ? 1 : 0
            clip: true

            Behavior on implicitWidth {
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }
            Behavior on opacity {
                NumberAnimation { duration: Motion.fast + entry.index * 60; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: entry.danger ? (hover.hovered ? Colors.error : Style.alpha(Colors.errorContainer, 0.9))
                     : (hover.hovered ? Colors.secondaryContainer : Style.alpha(Colors.textOnSurface, 0.06))
                scale: tap.pressed ? Style.pressScale : 1
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on scale {
                    NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                }
            }
            Row {
                id: label
                anchors.centerIn: parent
                spacing: 5
                readonly property color fg: entry.danger ? (hover.hovered ? Colors.textOnError : Colors.textOnErrorContainer)
                    : (hover.hovered ? Colors.textOnSecondaryContainer : Colors.textOnSurface)

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: entry.modelData.icon
                    size: 16
                    color: label.fg
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.modelData.label
                    weight: 600
                    color: label.fg
                }
            }
            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: tap; onTapped: root.action(entry.modelData.name) }
        }
    }

    // ⏻, turning into ✕ while open.
    Clickable {
        onClicked: root.open = !root.open

        Icon {
            name: root.open ? "close" : "power_settings_new"
            rotation: root.open ? 90 : 0
            Behavior on rotation {
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }
        }
    }
}
