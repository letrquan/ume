import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.common
import qs.services

// The first page: four tiles, the three sliders (and a volume per app),
// what's playing, and the battery with lock / settings / power.
Column {
    id: root

    spacing: 10

    // ---- Tiles (ctl): the ones in Style.controlTiles, in its order, with Edit
    // under them. Each tile lives in control/ControlTiles.qml (to add one: a
    // block there); control/TileGrid.qml lays them out and edits them.
    TileGrid {
        width: parent.width
    }

    // Sound: speaker, then mic; the arrow opens the device lists.
    Row {
        width: parent.width
        spacing: 6

        LevelSlider {
            width: parent.width - 44
            readonly property real v: ControlState.sink?.audio?.volume ?? 0
            value: v
            muted: ControlState.sink?.audio?.muted ?? false
            icon: muted || v === 0 ? "volume_off" : v < 0.34 ? "volume_mute" : v < 0.67 ? "volume_down" : "volume_up"
            onMoved: value => ControlState.setVolume(ControlState.sink, value)
            onIconClicked: ControlState.toggleMute(ControlState.sink)
        }
        Clickable {
            implicitHeight: Style.ccSliderHeight
            onClicked: ControlState.page = "audio"
            Icon { name: "tune"; size: 19 }
        }
    }

    // Apps playing sound: a slider for each (when any play).
    AppVolumes {
        width: parent.width - 44
    }

    LevelSlider {
        width: parent.width - 44
        visible: ControlState.source !== null
        value: ControlState.source?.audio?.volume ?? 0
        muted: ControlState.source?.audio?.muted ?? false
        icon: muted ? "mic_off" : "mic"
        onMoved: value => ControlState.setVolume(ControlState.source, value)
        onIconClicked: ControlState.toggleMute(ControlState.source)
    }

    // Brightness; the A beside it (where the speaker row has its arrow)
    // turns auto brightness on and off: lit while on.
    Row {
        width: parent.width
        spacing: 6
        visible: Brightness.ready

        LevelSlider {
            width: parent.width - 44
            value: Brightness.value
            canMute: false
            icon: Brightness.value < 0.34 ? "brightness_low" : Brightness.value < 0.67 ? "brightness_medium" : "brightness_high"
            onMoved: value => ControlState.setBrightness(Math.max(0.01, value))
        }
        Clickable {
            implicitHeight: Style.ccSliderHeight
            onClicked: ControlState.act("auto brightness " + !AutoBrightness.enabled, () => AutoBrightness.toggle())
            Icon {
                name: "brightness_auto"
                size: 19
                fill: AutoBrightness.enabled ? 1 : 0
                color: AutoBrightness.enabled ? Colors.primary : Colors.textOnSurfaceVariant
            }
        }
    }

    MediaCard {
        width: parent.width
    }

    // Battery, then lock / settings / power.
    Item {
        width: parent.width
        height: 36

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            visible: battery.isLaptopBattery

            readonly property var battery: UPower.displayDevice
            readonly property bool charging: battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.PendingCharge
            readonly property real seconds: charging ? battery.timeToFull : battery.timeToEmpty

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: parent.charging ? "battery_charging_full" : "battery_full"
                size: 18
                color: Colors.textOnSurfaceVariant
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                readonly property int h: Math.floor(parent.seconds / 3600)
                readonly property int m: Math.round((parent.seconds % 3600) / 60)
                text: Math.round(parent.battery.percentage * 100) + "%"
                      + (parent.seconds > 0 ? "  ·  " + (h > 0 ? h + "h " : "") + m + "m" + (parent.charging ? " to full" : " left") : "")
                role: "caption"
                color: Colors.textOnSurfaceVariant
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Clickable {
                onClicked: {
                    ControlState.close();
                    ControlState.act("lock", () => Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/qs-lock"]));
                }
                Icon { name: "lock"; size: 19 }
            }
            Clickable {
                onClicked: {
                    ControlState.close();
                    ControlState.act("settings", () => Panels.settings());
                }
                Icon { name: "settings"; size: 19 }
            }
            Clickable {
                onClicked: {
                    ControlState.close();
                    SessionState.show();
                }
                Icon { name: "power_settings_new"; size: 19 }
            }
        }
    }
}
