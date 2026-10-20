import QtQuick
import Quickshell.Services.UPower
import qs.common
import qs.services

// Live gauges: CPU, memory, temperature (the bar's SysStats, read only
// while this card is on screen) and the battery.
LockCard {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isLaptopBattery ?? false
    readonly property real percent: hasBattery ? (battery.percentage ?? 0) * 100 : 0
    readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging

    title: "System"
    titleIcon: "monitoring"

    Component.onCompleted: {
        SysStats.hold("cpu");
        SysStats.hold("memory");
        SysStats.hold("temperature");
    }
    Component.onDestruction: {
        SysStats.release("cpu");
        SysStats.release("memory");
        SysStats.release("temperature");
    }

    Grid {
        anchors.centerIn: parent
        columns: 2
        columnSpacing: 28
        rowSpacing: 10

        Gauge {
            icon: "memory"
            value: SysStats.cpu
            label: Math.round(SysStats.cpu * 100) + "%"
            accent: SysStats.cpu * 100 >= Style.statsWarnCpu ? Colors.error : Colors.primary
        }
        Gauge {
            icon: "memory_alt"
            value: SysStats.memory
            label: Math.round(SysStats.memory * 100) + "%"
            accent: SysStats.memory * 100 >= Style.statsWarnMemory ? Colors.error : Colors.secondary
        }
        Gauge {
            icon: "device_thermostat"
            value: SysStats.temp / 100
            label: Math.round(SysStats.temp) + "°C"
            accent: SysStats.temp >= Style.statsWarnTemp ? Colors.error : Colors.tertiary
        }
        Gauge {
            visible: root.hasBattery
            icon: root.charging ? "bolt" : "battery_horiz_075"
            value: root.percent / 100
            label: Math.round(root.percent) + "%"
            accent: root.percent <= Style.batteryLow && !root.charging ? Colors.error : Colors.primary
        }
    }
}
