pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.common
import "../common/sounds.js" as SoundFiles

// Small UI sounds (Settings → Sounds; each one can be turned off, one
// volume for all): the volume click, the screenshot shutter, recording
// start / stop, charger plugged in / out and, if wanted, Bluetooth devices
// coming and going. Locking and unlocking play from lock.qml (the lock is
// its own process). New-notification sounds stay in Notifs.qml.
// Which file each one plays: common/sounds.js.
//
// MINE_SOUNDS_DRYRUN=1 (tests): only prints the command.
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_SOUNDS_DRYRUN") === "1"

    // Quiet while the shell starts (everything reports its first values then).
    property bool armed: false
    Timer {
        running: true
        interval: 2000
        onTriggered: root.armed = true
    }

    // The same sound again within `gap` ms is dropped (one click per notch
    // when the volume is scrolled fast, not a burst). Sounds sharing a `key`
    // share that wait (plug / unplug: a loose cable doesn't chirp on and on).
    property var lastPlayed: ({})
    function play(name, gap, key) {
        if (!armed || Style.soundVolume <= 0)
            return;
        const k = key ?? name;
        const now = Date.now();
        if (now - (lastPlayed[k] ?? 0) < (gap ?? 60))
            return;
        lastPlayed[k] = now;
        const cmd = SoundFiles.command(name, Style.soundVolume);
        if (cmd.length === 0)
            return;
        if (dryRun)
            console.log("sounds (dry run):", name, JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // Each event, if its sound is on.
    function volumeTick() {
        if (Style.soundVolumeTick)
            play("volume", 80);
    }
    function screenshot() {
        if (Style.soundScreenshot)
            play("screenshot");
    }
    function recording(started) {
        if (Style.soundRecord)
            play(started ? "recordStart" : "recordStop");
    }
    function power(pluggedIn) {
        if (Style.soundPower)
            play(pluggedIn ? "plug" : "unplug", 1000, "power");
    }

    // Bluetooth devices connecting / going away (off by default; only
    // watched while it's on).
    Instantiator {
        model: Style.soundDevices ? Bluetooth.devices : null
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() {
                root.play(modelData.connected ? "deviceOn" : "deviceOff", 300, "device");
            }
        }
    }
}
