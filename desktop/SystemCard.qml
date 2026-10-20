import QtQuick
import qs.common
import qs.services
import qs.sysmon

// CPU, memory and temperature as small rings, and the network speed, on
// the desktop. SysStats only reads what someone holds, so this card holds
// its four kinds while it exists (and lets go when it's taken off).
DesktopCard {
    id: root

    readonly property var kinds: ["cpu", "memory", "temperature", "netspeed"]
    Component.onCompleted: kinds.forEach(k => SysStats.hold(k))
    Component.onDestruction: kinds.forEach(k => SysStats.release(k))

    implicitWidth: 320
    implicitHeight: 104

    Row {
        id: rings
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Ring {
            size: 50
            thickness: 4.5
            value: SysStats.cpu
            text: SysStats.cpuReady ? Math.round(SysStats.cpu * 100) + "%" : "…"
            label: "CPU"
            warn: SysStats.cpu * 100 >= Style.statsWarnCpu
        }
        Ring {
            size: 50
            thickness: 4.5
            value: SysStats.memory
            text: SysStats.memTotal > 0 ? Math.round(SysStats.memory * 100) + "%" : "…"
            label: "RAM"
            warn: SysStats.memory * 100 >= Style.statsWarnMemory
        }
        Ring {
            size: 50
            thickness: 4.5
            value: SysStats.temp / 100
            text: SysStats.tempSource !== "" ? Math.round(SysStats.temp) + "°" : "…"
            label: "Temp"
            warn: SysStats.temp >= Style.statsWarnTemp
        }
    }

    // ↓ 1.2 MB/s
    // ↑ 40 KB/s
    Column {
        anchors.left: rings.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
            model: [
                { icon: "arrow_downward", bps: () => SysStats.down },
                { icon: "arrow_upward", bps: () => SysStats.up }
            ]

            Row {
                required property var modelData
                spacing: 4

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: parent.modelData.icon
                    size: 15
                    color: Colors.primary
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysStats.netReady ? SysStats.speed(parent.modelData.bps()) : "…"
                    role: "label"
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }
}
