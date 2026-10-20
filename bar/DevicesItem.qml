import QtQuick
import qs.common
import qs.services

// The batteries of connected devices (headphones, mouse, game pad…): a
// small icon and the % for each, red when low, a bolt while charging.
// Only on the bar while something with a battery is connected; click: the
// control center's Bluetooth page.
Reveal {
    id: root

    // (`wanted`: the bar's slot reads it, see BarContent.)
    readonly property bool wanted: shown || implicitWidth > 0.5

    anchors.verticalCenter: parent?.verticalCenter
    shown: Peripherals.devices.length > 0

    Clickable {
        spacing: 10
        tip: "Devices"
        tipDetail: Peripherals.devices.map(d => d.name + " · " + d.percent + "%" + (d.charging ? " · charging" : "")).join("\n")
        onClicked: ControlState.toggle("bluetooth")

        Repeater {
            model: Peripherals.devices

            Row {
                required property var modelData
                readonly property bool low: modelData.percent < Style.deviceBatteryWarn && !modelData.charging

                anchors.verticalCenter: parent?.verticalCenter
                spacing: 3

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: parent.modelData.charging ? "bolt" : parent.modelData.glyph
                    size: 16
                    color: parent.low ? Colors.error : Colors.textOnSurface
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.percent + "%"
                    role: "body"
                    font.features: ({ "tnum": 1 })
                    color: parent.low ? Colors.error : Colors.textOnSurface
                }
            }
        }
    }
}
