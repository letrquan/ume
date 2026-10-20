import QtQuick
import Quickshell.Bluetooth
import qs.common
import qs.services

// Bluetooth off / on / connected. Click: the control center's Bluetooth page.
Clickable {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter?.enabled ?? false
    readonly property int connected: adapter ? adapter.devices.values.filter(d => d.connected).length : 0
    // Their names, for the tip (only worked out while it's showing).
    readonly property string names: Tooltips.source === root && adapter
        ? adapter.devices.values.filter(d => d.connected).map(d => (d.name || d.deviceName || d.address)
                                              + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "")).join("\n") : ""

    // Only with a Bluetooth adapter. (`wanted`: see BarContent.)
    readonly property bool wanted: adapter !== null

    visible: wanted
    tip: !root.powered ? "Bluetooth is off" : root.connected > 0 ? "Bluetooth" : "Bluetooth: nothing connected"
    tipDetail: root.names
    onClicked: ControlState.toggle("bluetooth")

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: !root.powered ? "bluetooth_disabled"
            : root.connected > 0 ? "bluetooth_connected"
            : "bluetooth"
        fill: root.powered ? 1 : 0
        opacity: root.powered ? 1 : 0.6
    }
}
