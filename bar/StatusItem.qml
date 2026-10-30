import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.common
import qs.services

// Wi-Fi, volume and battery as one button, like the status area of macOS,
// Windows 11 or GNOME: three glyphs, no numbers (the battery's shows while
// it's low or charging). Click: the control center; right click: its sound
// page; middle click: mute; scroll: volume (the OSD shows under it). The
// tip has the details. (The single items, network / volume / battery, are
// still there for the bar.)
Clickable {
    id: root

    // ---- Network (as NetworkIcon) ---------------------------------------------------------
    readonly property var devices: Networking.devices.values
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var network: wifi?.networks.values.find(n => n.connected) ?? null
    readonly property real strength: network?.signalStrength ?? 0   // 0-1
    readonly property bool online: wired !== null || network !== null

    // ---- Sound (as Volume) --------------------------------------------------------------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    // Without this the sink's volume and mute stay empty.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    // ---- Battery (as Battery) -----------------------------------------------------------
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isLaptopBattery ?? false
    readonly property real fraction: battery?.percentage ?? 0     // 0-1
    readonly property int percent: Math.round(fraction * 100)
    readonly property bool charging: battery?.state === UPowerDeviceState.Charging
                                     || battery?.state === UPowerDeviceState.PendingCharge
    readonly property bool low: !charging && percent <= Style.batteryLow

    spacing: 9
    padding: 9

    tip: (root.wired ? "Wired" + (root.wired.name ? " · " + root.wired.name : "")
          : !Networking.wifiEnabled ? "Wi-Fi is off"
          : root.network ? root.network.name + " · " + Math.round(root.strength * 100) + "% signal"
          : "Wi-Fi: not connected")
    tipDetail: [
        !root.sink ? "No sound output" : root.muted ? "Sound muted" : "Volume " + Math.round(root.volume * 100) + "%",
        root.hasBattery ? "Battery " + root.percent + "%" + (root.charging ? " · charging"
            : root.battery?.state === UPowerDeviceState.FullyCharged ? " · full" : "") : "",
        "Click: control center · scroll: volume"
    ].filter(s => s !== "").join("\n")
    tipShortcut: "mine:control-center"

    // This button on its screen: x from the bar window, which spans the screen.
    function itemRect() {
        const win = root.QsWindow.window;
        return win ? win.itemRect(root) : Qt.rect(0, 0, width, height);
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            ControlState.toggle("audio");
        else if (mouse.button === Qt.MiddleButton)
            ControlState.toggleMute(root.sink);
        else
            ControlState.toggle("main");
    }
    // One mouse notch = volumeStep; touchpads move it smoothly.
    onWheel: wheel => {
        if (!sink?.audio)
            return;
        const r = itemRect();
        OsdState.anchorTo(root.QsWindow.window?.screen?.name ?? "", r.x + r.width / 2);
        const delta = (wheel.angleDelta.y || -wheel.angleDelta.x) / 120;
        sink.audio.volume = Math.max(0, Math.min(1, volume + delta * Style.volumeStep));
        if (sink.audio.muted && delta > 0)
            sink.audio.muted = false;
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root.wired ? "lan"
            : !Networking.wifiEnabled ? "signal_wifi_off"
            : root.network === null ? "signal_wifi_statusbar_not_connected"
            : root.strength > 0.75 ? "signal_wifi_4_bar"
            : root.strength > 0.5 ? "network_wifi_3_bar"
            : root.strength > 0.25 ? "network_wifi_2_bar"
            : "network_wifi_1_bar"
        fill: root.online ? 1 : 0
        opacity: root.online ? 1 : 0.6
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root.muted || root.volume === 0 ? "volume_off"
            : root.volume < 0.34 ? "volume_mute"
            : root.volume < 0.67 ? "volume_down"
            : "volume_up"
        fill: root.muted ? 0 : 1
        opacity: root.muted ? 0.6 : 1
    }

    // The battery: a little drawn one, filled as far as it's charged (red
    // when low); the number and a bolt only while low or charging.
    Row {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasBattery
        spacing: 4

        Reveal {
            anchors.verticalCenter: parent.verticalCenter
            shown: root.low || root.charging

            Row {
                spacing: 1
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.charging
                    name: "bolt"
                    size: 14
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.percent + "%"
                    font.features: ({ "tnum": 1 })
                    color: root.low ? Colors.error : Colors.textOnSurface
                }
            }
        }

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 12

            Rectangle {
                id: shell
                anchors.verticalCenter: parent.verticalCenter
                width: 21
                height: 11
                radius: 3.5
                color: "transparent"
                border.width: 1.4
                border.color: Style.alpha(Colors.textOnSurface, 0.85)

                Rectangle {
                    x: 2.2
                    y: 2.2
                    height: parent.height - 4.4
                    width: Math.max(1.5, (parent.width - 4.4) * Math.min(1, root.fraction))
                    radius: 1.6
                    color: root.low ? Colors.error : Colors.textOnSurface

                    Behavior on width {
                        NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                    }
                }
            }
            // The nub.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: shell.width + 0.6
                width: 1.8
                height: 4.5
                radius: 0.9
                color: Style.alpha(Colors.textOnSurface, 0.75)
            }
        }
    }
}
