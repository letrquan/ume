pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.common

// What happens when you leave the laptop alone (times in Style.qml, Idle
// section; 0 = never):
//   dimAfter              the backlight glides down to a dim level
//   screenOffAfter        the screen goes off (mango's sleep_monitor)
//   lockAfter             the lock screen comes up (~/.local/bin/qs-lock)
//   lockedScreenOffAfter  the screen goes off this long after the lock
//                         screen is up (OLED: no still clock for minutes)
//   suspendOnBatteryAfter on battery, the laptop sleeps; not while music
//                         or a video plays, nor while something holds idle
//                         or sleep off (Keep awake, logind inhibitors)
// Both screen-off times are 0 by default until tried by hand (then 300 and
// 30): first `mmsg dispatch sleep_monitor,eDP-1; sleep 3; mmsg dispatch
// wakeup_monitor,eDP-1`, then that a key press brings the screen back.
// Any input undoes it: the screen comes back on and the brightness you had
// glides back. Apps that ask the system to stay awake (videos, calls) and
// "Keep awake" in the control center hold dim, screen off, lock and sleep
// off; not the screen off on the lock screen (nothing to watch behind it).
//
// With the presence sensor on (services/Presence.qml, Style.presenceLock):
// after presenceIdle s without input it is read every few seconds; nobody
// there for presenceAwayFor s locks right away; at dim time, someone
// looking holds the dim (and the screen off) until they look away or
// presenceDimHold s have passed. Never read while locked or after input.
//
// The screen always comes back: on input, on unlock, after the laptop slept
// (lid open is no input to mango), and when the shell starts (a crash while
// it was off): every output Quickshell or mango knows and the ones
// idle.json says were put to sleep get mango's wakeup_monitor.
//
// While dimmed or off, ~/.local/state/mine-shell/idle.json remembers the
// brightness to go back to, so a shell restart in the middle puts things
// back instead of leaving the screen dim (or off).
//
// MINE_IDLE_DRYRUN=1 (tests): only prints what it would do.
// MINE_IDLE_STATE: another file instead of idle.json.
// MINE_LOCK_CMD: instead of qs-lock. MINE_IDLE_ON_BATTERY=1|0: instead of UPower.
Singleton {
    id: root

    // The control center's "Keep awake" tile (not kept across restarts).
    property bool keepAwake: false

    readonly property bool dryRun: Quickshell.env("MINE_IDLE_DRYRUN") === "1"
    readonly property bool dimmed: dimOn
    readonly property bool screenOff: off

    function run(what, cmd) {
        if (dryRun)
            console.log("idle (dry run):", what, JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // ---- Dim ----------------------------------------------------------------------
    // The brightness before dimming, to bring back.
    property real before: -1
    // Glide the backlight in a few steps (brightnessctl has no fade).
    property real glideFrom: 0
    property real glideTo: 0
    property int glideStep: 0
    readonly property int glideSteps: 8

    // True while gliding (and a moment after, for the last change to come
    // back from sysfs), so the brightness OSD doesn't pop up for it.
    readonly property bool quietBrightness: glider.running || quietTail.running

    function glide(to) {
        if (!Brightness.ready)
            return;
        glideFrom = Brightness.value;
        glideTo = to;
        glideStep = 0;
        glider.restart();
    }
    Timer {
        id: glider
        interval: 60
        repeat: true
        onTriggered: {
            root.glideStep++;
            const t = root.glideStep / root.glideSteps;
            const v = root.glideFrom + (root.glideTo - root.glideFrom) * t;
            if (root.dryRun)
                console.log("idle (dry run): brightness", v.toFixed(2));
            else
                Brightness.set(v);
            if (root.glideStep >= root.glideSteps) {
                stop();
                quietTail.restart();
            }
        }
    }
    Timer {
        id: quietTail
        interval: 800
    }

    function dim(on) {
        if (on) {
            if (!Brightness.ready || Brightness.value <= Style.idleDimLevel)
                return;
            before = Brightness.value;
            save();
            glide(Style.idleDimLevel);
        } else if (before >= 0) {
            glide(before);
            before = -1;
            save();
        }
    }

    // Dimmed or not, as asked (the presence check can put it off).
    property bool dimOn: false
    function setDim(on) {
        if (on === dimOn)
            return;
        dimOn = on;
        dim(on);
    }

    // dimAt went idle (or back): with the sensor, ask first (not when the
    // screen is off already: asking holds it, which would turn it back on).
    function dimIdle(idle) {
        if (!idle) {
            asking = false;
            askTimeout.stop();
            release();
            setDim(false);
        } else if (Presence.enabled && Presence.device !== "" && !locked && !off) {
            asking = true;
            askTimeout.restart();
            Presence.ask();
        } else {
            setDim(true);
        }
    }

    // ---- Someone looking (presence sensor) -------------------------------------------
    // The dim-time read is out.
    property bool asking: false
    // Someone was looking at dim time: dim and screen off wait.
    property bool watched: false
    // Locked by the sensor in this idle stretch (only once: the hyprlock
    // fallback leaves no marker, so it would lock again and again).
    property bool presenceLocked: false

    function release() {
        watched = false;
        holdCap.stop();
        if (dimAt.isIdle && !asking)
            setDim(true);
    }

    // No answer in time (the camera didn't wake): dim as usual.
    Timer {
        id: askTimeout
        interval: 5000
        onTriggered: {
            root.asking = false;
            if (dimAt.isIdle)
                root.setDim(true);
        }
    }
    // A sensor stuck on "someone there" must not keep the screen bright.
    Timer {
        id: holdCap
        interval: Math.max(1, Style.presenceDimHold) * 1000
        onTriggered: {
            console.log("idle: held the dim for someone looking long enough");
            root.release();
        }
    }

    Connections {
        target: Presence
        function onAnswered(looking, known) {
            if (!root.asking)
                return;
            root.asking = false;
            askTimeout.stop();
            if (!dimAt.isIdle)
                return;
            if (known && looking && !root.locked) {
                console.log("idle: someone is looking, the dim waits");
                root.watched = true;
                holdCap.restart();
            } else {
                root.setDim(true);
            }
        }
        function onReading(present, looking, known) {
            if (root.watched && known && !looking) {
                console.log("idle: nobody looking any more, dimming");
                root.release();
            }
        }
        function onAway() {
            if (!presenceAt.isIdle || root.locked || root.presenceLocked)
                return;
            root.presenceLocked = true;
            console.log("idle: nobody in front of the screen for", Style.presenceAwayFor, "s, locking");
            root.lock();
        }
    }

    // Turned on or off: start over (off: nothing it said holds anything).
    readonly property bool presenceOn: Presence.enabled
    onPresenceOnChanged: {
        presenceLocked = false;
        if (asking) {
            asking = false;
            askTimeout.stop();
        }
        release();
    }

    // Read the sensor while idle long enough (or while the dim waits for
    // someone looking), not locked, and not just locked by it.
    Binding {
        target: Presence
        property: "watching"
        value: (presenceAt.isIdle || root.watched) && !root.locked && !root.presenceLocked
    }
    // While the dim waits, every read also asks whether they still look.
    Binding {
        target: Presence
        property: "wantAttention"
        value: root.watched
    }

    // ---- Lock screen ----------------------------------------------------------------
    // lock.qml creates $XDG_RUNTIME_DIR/qs-lock.secure once the compositor
    // has locked, and removes it on unlock. Watched only while needed.
    readonly property string marker: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-lock.secure"
    property bool markerThere: false
    readonly property bool locked: markerFile.path !== "" && markerThere

    FileView {
        id: markerFile
        path: Style.lockedScreenOffAfter > 0 || Presence.enabled ? root.marker : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.markerThere = true
        onLoadFailed: root.markerThere = false
    }
    onLockedChanged: {
        if (locked && watched)
            release();
    }

    // ---- Screen off -----------------------------------------------------------------
    // Off when idle long enough (unless someone is looking), or when the lock
    // screen has been up long enough without input. One property for both,
    // so neither can turn the screen on while the other wants it off.
    readonly property bool wantOff: (offAt.isIdle && !asking && !watched) || lockOffAt.isIdle
    onWantOffChanged: screens(!wantOff)

    property bool off: false
    // The outputs put to sleep (kept in idle.json), woken first.
    property var asleep: []

    function screenNames() {
        return Quickshell.screens.map(s => s.name).filter(n => n !== "");
    }
    function wake(names, why) {
        const seen = {};
        for (const n of names) {
            if (n === "" || seen[n])
                continue;
            seen[n] = true;
            run(why, ["mmsg", "dispatch", "wakeup_monitor," + n]);
        }
    }

    function screens(on) {
        if (on) {
            if (!off)
                return;
            console.log("idle: screen on");
            wake(asleep.concat(screenNames()), "screen on");
            asleep = [];
            off = false;
            save();
        } else {
            if (off)
                return;
            asleep = screenNames();
            off = true;
            save();
            console.log("idle: screen off", lockOffAt.isIdle ? "(lock screen up " + Style.lockedScreenOffAfter + " s)" : "");
            for (const n of asleep)
                run("screen off", ["mmsg", "dispatch", "sleep_monitor," + n]);
        }
    }

    // ---- After the laptop slept ----------------------------------------------------------
    // Opening the lid is no input to mango, so a screen that was off when
    // the laptop went to sleep would stay black: on waking up, the screen
    // off timers start over (screen on, off again after the usual time).
    // Known through services/Locker.qml (only while Lock before sleep is on).
    readonly property bool systemAsleep: Locker.sleeping
    property bool rearm: false
    onSystemAsleepChanged: {
        if (!systemAsleep && off) {
            console.log("idle: woke from sleep, screen on");
            rearm = true;
            Qt.callLater(() => root.rearm = false);
        }
    }

    // ---- After a restart ---------------------------------------------------------------
    readonly property string statePath: Quickshell.env("MINE_IDLE_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/idle.json")

    function save() {
        stateFile.setText(before < 0 && !off ? "{}\n" : JSON.stringify({ before: before, off: off, outputs: asleep }, null, 1));
    }

    // Every output there is: Quickshell's, idle.json's, and mango's own list
    // (once, in case one went missing from Wayland while asleep).
    function wakeAll(why, names) {
        console.log("idle: waking every screen (" + why + ")");
        wake(names.concat(screenNames()), why);
        if (!monitorList.asked) {
            monitorList.asked = true;
            monitorList.why = why;
            monitorList.running = true;
        }
    }
    Process {
        id: monitorList
        property bool asked: false
        property string why: ""
        command: ["mmsg", "get", "all-monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                let names = [];
                try {
                    names = (JSON.parse(text).monitors ?? []).map(m => m.name ?? "");
                } catch (e) {
                    return;
                }
                root.wake(names.filter(n => !root.screenNames().includes(n)), monitorList.why);
            }
        }
    }
    // Only when screen off is on (or idle.json says a screen is off), so
    // with both times at 0 nothing runs.
    Component.onCompleted: {
        if (Style.screenOffAfter > 0 || Style.lockedScreenOffAfter > 0)
            wakeAll("shell start", []);
    }

    // Read once at start: dimmed or off when the last shell stopped -> undo.
    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        printErrors: false

        onLoaded: {
            let saved = {};
            try {
                saved = JSON.parse(text() || "{}");
            } catch (e) {
                return;
            }
            if (saved.off)
                root.wakeAll("was off when the shell stopped", saved.outputs ?? []);
            if (saved.before > 0)
                restore.saved = saved.before;
        }
    }
    // The brightness is known only once Brightness is ready.
    Timer {
        id: restore
        property real saved: -1
        running: saved > 0
        interval: 200
        repeat: true
        onTriggered: {
            if (!Brightness.ready)
                return;
            console.log("idle: was dimmed when the shell stopped, back to", Math.round(saved * 100) + "%");
            root.glide(saved);
            saved = -1;
            root.save();
        }
    }

    // ---- Lock -----------------------------------------------------------------------------
    readonly property string lockCmd: Quickshell.env("MINE_LOCK_CMD") || (Quickshell.env("HOME") + "/.local/bin/qs-lock")
    function lock() {
        run("lock", [lockCmd]);
    }

    // ---- Sleep on battery -----------------------------------------------------------------
    readonly property string fakeBattery: Quickshell.env("MINE_IDLE_ON_BATTERY")
    readonly property bool unplugged: Style.suspendOnBatteryAfter > 0
        && (fakeBattery !== "" ? fakeBattery === "1" : UPower.onBattery)
    // Bound while armed, so the player list is filled in by the time it counts.
    readonly property bool playing: unplugged && Mpris.players.values.some(p => p.isPlaying)
    // Asked once per idle stretch.
    property bool suspended: false

    function trySuspend() {
        if (!suspendAt.isIdle || suspended)
            return;
        if (playing) {
            console.log("idle: not sleeping, something is playing");
            suspendRetry.restart();
            return;
        }
        blockCheck.running = true;
    }
    // Something holding idle or sleep off through logind (systemd-inhibit).
    Process {
        id: blockCheck
        command: ["busctl", "--system", "get-property", "org.freedesktop.login1", "/org/freedesktop/login1",
                  "org.freedesktop.login1.Manager", "BlockInhibited"]
        stdout: StdioCollector {
            onStreamFinished: {
                const what = text.trim().replace(/^s\s+"|"$/g, "").split(":");
                if (what.includes("idle") || what.includes("sleep")) {
                    console.log("idle: not sleeping, held off by logind:", what.join(" "));
                    suspendRetry.restart();
                } else if (suspendAt.isIdle && !root.suspended) {
                    root.suspended = true;
                    console.log("idle: on battery and idle, sleeping");
                    root.run("sleep", ["systemctl", "suspend"]);
                }
            }
        }
    }
    // Try again later while still idle (the music may stop).
    Timer {
        id: suspendRetry
        interval: 60000
        onTriggered: root.trySuspend()
    }

    // ---- When ------------------------------------------------------------------------------
    // respectInhibitors: videos, calls and our own Keep awake (Bar.qml's
    // IdleInhibitor) hold these off.
    IdleMonitor {
        id: dimAt
        enabled: Style.dimAfter > 0
        timeout: Math.max(1, Style.dimAfter)
        respectInhibitors: true
        onIsIdleChanged: root.dimIdle(isIdle)
    }
    IdleMonitor {
        id: offAt
        enabled: Style.screenOffAfter > 0 && !root.rearm
        timeout: Math.max(1, Style.screenOffAfter)
        respectInhibitors: true
    }
    IdleMonitor {
        id: lockAt
        enabled: Style.lockAfter > 0
        timeout: Math.max(1, Style.lockAfter)
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.lock()
    }
    // Made when the lock screen comes up, so it counts from then. Not held
    // off by inhibitors: an app behind the lock must not keep a still
    // picture lit on the OLED.
    IdleMonitor {
        id: lockOffAt
        enabled: Style.lockedScreenOffAfter > 0 && root.locked && !root.rearm
        timeout: Math.max(1, Style.lockedScreenOffAfter)
        respectInhibitors: false
    }
    IdleMonitor {
        id: presenceAt
        enabled: Presence.enabled
        timeout: Math.max(1, Style.presenceIdle)
        respectInhibitors: true
        onIsIdleChanged: if (!isIdle) root.presenceLocked = false
    }
    IdleMonitor {
        id: suspendAt
        enabled: root.unplugged
        timeout: Math.max(1, Style.suspendOnBatteryAfter)
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle) {
                root.trySuspend();
            } else {
                root.suspended = false;
                suspendRetry.stop();
            }
        }
    }
}
