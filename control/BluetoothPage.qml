import QtQuick
import Quickshell.Bluetooth
import qs.common
import qs.services

// Bluetooth devices: yours (paired) first, then new ones found while
// "Scan" is on. Click to connect / disconnect, or to pair a new one.
Column {
    id: root

    spacing: 6

    readonly property var adapter: ControlState.adapter
    readonly property bool powered: adapter?.enabled ?? false
    readonly property var devices: {
        const list = (adapter?.devices.values ?? []).filter(d => d.name !== "" && d.name !== d.address.replace(/:/g, "-"));
        return list.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name));
    }
    readonly property var mine: devices.filter(d => d.paired)
    readonly property var found: devices.filter(d => !d.paired)

    Component.onDestruction: ControlState.setDiscovering(false)

    function deviceIcon(d) {
        const icon = d.icon ?? "";
        if (icon.includes("headset") || icon.includes("headphone"))
            return "headphones";
        if (icon.includes("audio"))
            return "speaker";
        if (icon.includes("mouse"))
            return "mouse";
        if (icon.includes("keyboard"))
            return "keyboard";
        if (icon.includes("phone"))
            return "smartphone";
        if (icon.includes("gaming"))
            return "sports_esports";
        if (icon.includes("computer"))
            return "computer";
        return "bluetooth";
    }

    function status(d) {
        if (d.state === BluetoothDeviceState.Connecting)
            return "Connecting…";
        if (d.state === BluetoothDeviceState.Disconnecting)
            return "Disconnecting…";
        if (d.pairing)
            return "Pairing…";
        const battery = d.batteryAvailable ? "  ·  " + Math.round(d.battery * 100) + "%" : "";
        return (d.connected ? "Connected" : d.paired ? "Saved" : "New") + battery;
    }

    PageHeader {
        width: parent.width
        title: "Bluetooth"
        hasSwitch: true
        checked: root.powered
        onFlipped: ControlState.setBluetooth(!root.powered)

        // Scan for new devices.
        Clickable {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.powered
            implicitHeight: 32
            padding: 12
            onClicked: ControlState.setDiscovering(!(root.adapter?.discovering ?? false))

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "radar"
                size: 18
                color: root.adapter?.discovering ? Colors.primary : Colors.textOnSurface

                RotationAnimation on rotation {
                    running: root.adapter?.discovering ?? false
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 2000
                }
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.adapter?.discovering ? "Scanning" : "Scan"
                role: "label"
                color: root.adapter?.discovering ? Colors.primary : Colors.textOnSurface
            }
        }
    }

    EmptyState {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !root.powered || root.devices.length === 0
        textWidth: parent.width - 32
        shape: root.powered ? "Clover4Leaf" : "Cookie9Sided"
        icon: !root.powered ? "bluetooth_disabled" : root.adapter?.discovering ? "bluetooth_searching" : "bluetooth"
        title: !root.powered ? "Bluetooth is off" : "No devices yet"
        hint: !root.powered ? "Turn it on above to see your devices"
            : root.adapter?.discovering ? "Looking for devices nearby…" : "Press Scan to find some"
    }

    Flickable {
        width: parent.width
        height: Math.min(contentHeight, 6 * 50)
        visible: root.powered && root.devices.length > 0
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: parent.width
            spacing: 2

            Repeater {
                model: root.mine.concat(root.found)

                ListItem {
                    required property var modelData
                    readonly property var d: modelData

                    width: list.width
                    icon: root.deviceIcon(d)
                    label: d.name
                    detail: root.status(d)
                    current: d.connected
                    busy: d.state === BluetoothDeviceState.Connecting || d.pairing
                    onClicked: ControlState.useDevice(d)
                }
            }
        }
    }
}
