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

    Grid {
        width: parent.width
        columns: 2
        columnSpacing: 8
        rowSpacing: 8

        Tile {
            width: (parent.width - 8) / 2
            icon: ControlState.wiredDevice ? "lan" : Networking.wifiEnabled ? "wifi" : "wifi_off"
            label: ControlState.wiredDevice ? "Ethernet" : "Wi-Fi"
            detail: ControlState.wiredDevice ? "Connected"
                  : !Networking.wifiEnabled ? "Off"
                  : ControlState.wifiNetwork?.name ?? "Not connected"
            active: ControlState.wiredDevice !== null || Networking.wifiEnabled
            hasPage: true
            onToggled: ControlState.setWifi(!Networking.wifiEnabled)
            onOpenPage: ControlState.page = "wifi"
        }

        Tile {
            width: (parent.width - 8) / 2
            readonly property bool powered: ControlState.adapter?.enabled ?? false
            icon: !powered ? "bluetooth_disabled" : ControlState.btConnected.length > 0 ? "bluetooth_connected" : "bluetooth"
            label: "Bluetooth"
            detail: !ControlState.adapter ? "No adapter"
                  : !powered ? "Off"
                  : ControlState.btConnected.length === 1
                    ? ControlState.btConnected[0].name + (Peripherals.levelOf(ControlState.btConnected[0]) !== "" ? " · " + Peripherals.levelOf(ControlState.btConnected[0]) : "")
                  : ControlState.btConnected.length > 1 ? ControlState.btConnected.length + " devices"
                  : "On"
            active: powered
            hasPage: ControlState.adapter !== null
            onToggled: ControlState.setBluetooth(!powered)
            onOpenPage: ControlState.page = "bluetooth"
        }

        Tile {
            width: (parent.width - 8) / 2
            icon: Notifs.dnd ? "do_not_disturb_on" : "notifications"
            label: "Silent"
            detail: Notifs.dnd ? "Notifications muted" : "Off"
            active: Notifs.dnd
            onToggled: Notifs.toggleDnd()
        }

        Tile {
            width: (parent.width - 8) / 2
            icon: "coffee"
            label: "Keep awake"
            detail: Idle.keepAwake ? "Screen stays on" : "Off"
            active: Idle.keepAwake
            onToggled: Idle.keepAwake = !Idle.keepAwake
        }

        // Right-click: all the time <-> at night.
        Tile {
            width: (parent.width - 8) / 2
            icon: "nightlight"
            label: "Night light"
            detail: NightLight.detail
            active: NightLight.isOn && NightLight.available
            hasSecondary: true
            onToggled: NightLight.toggle()
            onSecondary: NightLight.cycle()
        }

        // Click: dark <-> light; right click: auto (light by day).
        Tile {
            width: (parent.width - 8) / 2
            icon: Theme.dark ? "dark_mode" : "light_mode"
            label: "Dark mode"
            detail: Theme.mode === "auto" ? "Auto · " + (Theme.dark ? "night" : "day") : (Theme.dark ? "On" : "Off")
            active: Theme.dark
            hasSecondary: true
            onToggled: Theme.toggle()
            onSecondary: Theme.cycleAuto()
        }

        Tile {
            width: (parent.width - 8) / 2
            icon: "screenshot_region"
            label: "Screenshot"
            detail: "Pick a region"
            onToggled: {
                ControlState.close();
                shotLater.start();      // once the control center is out of the picture
            }

            Timer {
                id: shotLater
                interval: Motion.morphOut + 150
                onTriggered: Screenshot.region()
            }
        }

        // Screen recording: click records the screen, right click (or a
        // long press) picks a region first; click again to stop.
        Tile {
            width: (parent.width - 8) / 2
            icon: "screen_record"
            label: Recorder.recording ? "Recording" : "Record"
            detail: Recorder.recording ? Recorder.elapsedText + " · click to stop" : "Right-click: a region"
            active: Recorder.recording
            hasSecondary: true
            onToggled: {
                if (Recorder.recording) {
                    Recorder.stop();
                    return;
                }
                ControlState.close();
                Recorder.startSoon("screen");
            }
            onSecondary: {
                if (Recorder.recording) {
                    Recorder.stop();
                    return;
                }
                ControlState.close();
                Recorder.startSoon("region");
            }
        }

        Tile {
            width: (parent.width - 8) / 2
            readonly property int profile: PowerProfiles.profile
            icon: profile === PowerProfile.PowerSaver ? "eco" : profile === PowerProfile.Performance ? "bolt" : "balance"
            label: "Power mode"
            detail: profile === PowerProfile.PowerSaver ? "Saver" : profile === PowerProfile.Performance ? "Performance" : "Balanced"
            active: profile !== PowerProfile.Balanced
            onToggled: ControlState.nextProfile()
        }

        // Turning the screen with the tablet (Settings → On-screen keyboard →
        // Tablet): only while that's on. Click: hold the screen as it is.
        Tile {
            width: (parent.width - 8) / 2
            visible: AutoRotate.enabled
            icon: AutoRotate.locked ? "mobile_rotate_lock" : "mobile_rotate"
            label: "Auto-rotate"
            detail: AutoRotate.locked ? "Held as it is" : AutoRotate.active ? "On" : "In tablet mode"
            active: !AutoRotate.locked
            onToggled: AutoRotate.toggleLock()
        }

        // Your phone (KDE Connect): only once it's installed. Click: its page.
        Tile {
            width: (parent.width - 8) / 2
            visible: Style.ccPhone && Phone.installed
            icon: Phone.connected ? Phone.glyphFor(Phone.device) : "phonelink_off"
            label: Phone.device?.name ?? "Phone"
            detail: Phone.summary
            active: Phone.connected
            hasPage: true
            onToggled: ControlState.page = "phone"
            onOpenPage: ControlState.page = "phone"
            Component.onCompleted: Phone.use(true)
            Component.onDestruction: Phone.use(false)
        }
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

    LevelSlider {
        width: parent.width - 44
        visible: Brightness.ready
        value: Brightness.value
        canMute: false
        icon: Brightness.value < 0.34 ? "brightness_low" : Brightness.value < 0.67 ? "brightness_medium" : "brightness_high"
        onMoved: value => ControlState.setBrightness(Math.max(0.01, value))
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
