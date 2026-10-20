import QtQuick
import Quickshell.Networking
import qs.common
import qs.services

// Wired or Wi-Fi (with signal bars). Click: the control center's Wi-Fi page.
Clickable {
    id: root

    readonly property var devices: Networking.devices.values
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var network: wifi?.networks.values.find(n => n.connected) ?? null
    readonly property real strength: network?.signalStrength ?? 0   // 0-1

    tip: root.wired ? "Wired" + (root.wired.name ? " · " + root.wired.name : "")
        : !Networking.wifiEnabled ? "Wi-Fi is off"
        : root.network ? root.network.name
        : "Wi-Fi: not connected"
    tipDetail: !root.wired && root.network ? Math.round(root.strength * 100) + "% signal" : ""
    onClicked: ControlState.toggle("wifi")

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root.wired ? "lan"
            : !Networking.wifiEnabled ? "signal_wifi_off"
            : root.network === null ? "signal_wifi_statusbar_not_connected"
            : root.strength > 0.75 ? "signal_wifi_4_bar"
            : root.strength > 0.5 ? "network_wifi_3_bar"
            : root.strength > 0.25 ? "network_wifi_2_bar"
            : "network_wifi_1_bar"
        fill: root.wired || root.network ? 1 : 0
        opacity: root.wired || root.network ? 1 : 0.6
    }
}
