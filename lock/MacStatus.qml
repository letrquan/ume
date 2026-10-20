import QtQuick
import QtQuick.Effects
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.common

// The mac style's top-right corner, small and white like a Mac's menu bar
// on the lock screen: the keyboard layout, Wi-Fi and the battery.
Row {
    id: root

    spacing: 14

    // 0 → 1 as the picture behind gets bright: a stronger shadow.
    property real boost: 0
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isLaptopBattery ?? false
    readonly property real percent: hasBattery ? (battery.percentage ?? 0) * 100 : 0
    readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging

    readonly property var devices: Networking.devices.values
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var network: wifi?.networks.values.find(n => n.connected) ?? null
    readonly property real strength: network?.signalStrength ?? 0

    // mango's keyboard layout, once ("English (US)" → "EN").
    property string layout: ""
    Process {
        running: true
        command: ["mmsg", "get", "keyboardlayout"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const name = JSON.parse(this.text).layout ?? "";
                    root.layout = name.slice(0, 2).toUpperCase();
                } catch (e) {}
            }
        }
    }

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.35 + 0.35 * root.boost)
        shadowBlur: 0.5 + 0.3 * root.boost
        shadowVerticalOffset: 1
    }

    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.layout !== ""
        text: root.layout
        color: "white"
        weight: 600
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        size: 18
        color: "white"
        name: root.wired ? "lan"
            : !Networking.wifiEnabled ? "signal_wifi_off"
            : root.network === null ? "signal_wifi_statusbar_not_connected"
            : root.strength > 0.75 ? "signal_wifi_4_bar"
            : root.strength > 0.5 ? "network_wifi_3_bar"
            : root.strength > 0.25 ? "network_wifi_2_bar"
            : "network_wifi_1_bar"
        opacity: root.wired || root.network ? 1 : 0.6
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasBattery
        spacing: 4

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.percent) + "%"
            color: "white"
            weight: 600
            font.features: ({ "tnum": 1 })
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            size: 20
            color: "white"
            rotation: 90
            name: root.charging ? "battery_charging_full"
                : root.percent >= 95 ? "battery_full"
                : "battery_" + Math.max(0, Math.min(6, Math.floor(root.percent / 100 * 7))) + "_bar"
        }
    }
}
