pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.common

// Looking after the battery (Settings → Power & locking → Battery):
//  - Unplugged: the power mode goes to Power saver; plugged back in, it
//    goes back to what it was before (Style.batterySaverOnBattery).
//    Changing it by hand while unplugged is left alone until you plug in.
//  - A warning at Style.batteryWarnLow and an urgent one at
//    Style.batteryWarnCritical (it plays the sound and shows even when
//    Silent), each once per discharge; charging resets them.
//  - Optional: "Charged" at Style.batteryFullNotice (0 = off).
// ~/.local/state/mine-shell/battery.json keeps the mode to go back to and
// which warnings were shown, so a shell restart doesn't undo or repeat them.
//
// Tests: MINE_BATTERY_DRYRUN=1 only prints what it would do;
// MINE_BATTERY_FAKE=1 reads fakePercent / fakeUnplugged instead of UPower;
// MINE_BATTERY_STATE: another file instead of battery.json.
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_BATTERY_DRYRUN") === "1"
    readonly property bool fake: Quickshell.env("MINE_BATTERY_FAKE") === "1"
    property real fakePercent: 50
    property bool fakeUnplugged: true

    readonly property var device: UPower.displayDevice
    readonly property bool hasBattery: fake || (device?.isLaptopBattery ?? false)
    readonly property int percent: fake ? Math.round(fakePercent) : Math.round((device?.percentage ?? 0) * 100)
    // (Not `onBattery`: QML reads on + capital letter as a signal handler.)
    readonly property bool unplugged: fake ? fakeUnplugged : UPower.onBattery
    readonly property real secondsLeft: fake ? 0 : (device?.timeToEmpty ?? 0)

    // ---- State that outlives a restart --------------------------------------------
    property bool loaded: false
    property int savedProfile: -1         // the mode to go back to when plugged in, -1 = none
    property bool warnedLow: false
    property bool warnedCritical: false
    property bool toldFull: false

    readonly property string statePath: Quickshell.env("MINE_BATTERY_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/battery.json")

    function save() {
        if (!loaded)
            return;
        stateFile.setText(JSON.stringify({
            savedProfile: savedProfile, warnedLow: warnedLow,
            warnedCritical: warnedCritical, toldFull: toldFull
        }, null, 1));
    }

    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        printErrors: false

        // (After the load has finished: restore() may save right away.)
        onLoaded: {
            const saved = text();
            Qt.callLater(() => root.restore(saved));
        }
        onLoadFailed: Qt.callLater(() => root.restore(""))
    }

    function restore(text) {
        let s = {};
        try {
            s = JSON.parse(text || "{}");
        } catch (e) {}
        savedProfile = s.savedProfile ?? -1;
        warnedLow = s.warnedLow ?? false;
        warnedCritical = s.warnedCritical ?? false;
        toldFull = s.toldFull ?? false;
        loaded = true;
        // What happened while the shell wasn't running.
        plugChanged();
        check();
    }

    // ---- Doing things ---------------------------------------------------------------
    function profileName(p) {
        return p === PowerProfile.PowerSaver ? "power saver"
             : p === PowerProfile.Performance ? "performance" : "balanced";
    }

    function setProfile(p) {
        if (dryRun)
            console.log("battery (dry run): power mode", profileName(p));
        else
            PowerProfiles.profile = p;
    }

    function notify(urgency, icon, summary, body) {
        const cmd = ["notify-send", "-a", "Battery", "-u", urgency, "-i", icon,
                     "-h", "string:category:device", summary, body];
        if (dryRun)
            console.log("battery (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    function timeLeft() {
        const s = secondsLeft;
        if (s <= 0)
            return "";
        const h = Math.floor(s / 3600);
        const m = Math.round((s % 3600) / 60);
        return " · about " + (h > 0 ? h + " h " + m + " min" : m + " min") + " left";
    }

    // ---- Plugged in / unplugged ------------------------------------------------------
    // Also run once at start (with the saved state), so a restart in between
    // behaves as if the shell had been there.
    function plugChanged() {
        if (!loaded || !hasBattery)
            return;
        if (unplugged) {
            toldFull = false;
            if (Style.batterySaverOnBattery && savedProfile < 0
                    && PowerProfiles.profile !== PowerProfile.PowerSaver) {
                savedProfile = PowerProfiles.profile;
                setProfile(PowerProfile.PowerSaver);
            }
        } else {
            warnedLow = false;
            warnedCritical = false;
            if (savedProfile >= 0) {
                setProfile(savedProfile);
                savedProfile = -1;
            }
        }
        save();
    }
    onUnpluggedChanged: {
        plugChanged();
        if (loaded && hasBattery)
            Sounds.power(!unplugged);
    }
    onHasBatteryChanged: plugChanged()

    // ---- Warnings ----------------------------------------------------------------------
    function check() {
        if (!loaded || !hasBattery || percent <= 0)
            return;
        if (unplugged) {
            if (percent <= Style.batteryWarnCritical && !warnedCritical) {
                warnedCritical = true;
                warnedLow = true;
                notify("critical", "battery-empty", "Battery almost empty",
                       percent + "%" + timeLeft() + ". Plug in now, or save your work.");
                save();
            } else if (percent <= Style.batteryWarnLow && !warnedLow) {
                warnedLow = true;
                notify("normal", "battery-caution", "Battery low",
                       percent + "%" + timeLeft() + ".");
                save();
            }
        } else if (Style.batteryFullNotice > 0 && percent >= Style.batteryFullNotice && !toldFull) {
            toldFull = true;
            notify("normal", "battery-full-charged", "Battery charged",
                   percent + "%. You can unplug now.");
            save();
        }
    }
    onPercentChanged: check()
}
