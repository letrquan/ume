pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.common
import "screentime.js" as Count

// Screen time: how long each app had you, per day, for the "Screen time"
// bar item and popup (bar/ScreenTimeItem.qml, control/ScreenTimePopup.qml),
// the control center tile and the break reminders (services/Breaks.qml).
//
// What counts: the focused window's app (Quickshell's ToplevelManager: the
// window mango says is active, by its app id; no process runs for it),
// while you're really there:
//  - the screen is on (Idle's screen off, passed in by shell.qml), the lock
//    screen isn't up (lock.qml's $XDG_RUNTIME_DIR/qs-lock.secure), the
//    laptop isn't asleep (Locker; and a gap in the minute ticks, for sleeps
//    it didn't see);
//  - and there was input in the last Style.screenTimeIdle seconds. When
//    that runs out, counting stops at your last input (not at the moment
//    it ran out). Except while the focused window is fullscreen, or a
//    player in the focused app plays (a video in the browser): that goes on
//    counting while idle, until it stops playing or the window goes.
// Nothing ticks per second: a stretch of one app starts and ends on events
// (focus, idle, lock, sleep) with their times. Once a minute (while one
// counts) what's counted so far goes into the day, and the file is saved;
// also on shutdown, log out and lock (shell.qml). A crash loses at most
// that last minute.
//
// ~/.local/state/mine-shell/screentime.json: { version, days: { "YYYY-MM-DD":
// { "<app id>": seconds } } }, local dates, the last Style.screenTimeDays
// days. Saved through StateFile (a planted link there is never followed).
//
// MINE_SCREENTIME_STATE: another file; MINE_SCREENTIME_FLUSH: seconds
// instead of the minute. MINE_SCREENTIME_FAKEFOCUS=1 (tests):
// the focused app is `fakeApp` (and `fakeFullscreen`), not the compositor's;
// idle comes only from noteIdle().
Singleton {
    id: root

    // Counting per app (saved). The rest (here or away) also runs for the
    // break reminders while those are on.
    readonly property bool enabled: Style.screenTime
    readonly property bool watching: enabled || Style.breakReminders || Style.breakEyes
    readonly property string statePath: Quickshell.env("MINE_SCREENTIME_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/screentime.json")

    // ---- What has you right now -----------------------------------------------------------
    readonly property bool fakeFocus: Quickshell.env("MINE_SCREENTIME_FAKEFOCUS") === "1"
    property string fakeApp: ""
    property bool fakeFullscreen: false

    readonly property var toplevel: fakeFocus ? null : ToplevelManager.activeToplevel
    // (activeToplevel stays the last one while no window is focused: an
    // empty workspace. `activated` says whether it still is.)
    readonly property string focusedApp: fakeFocus ? fakeApp
        : toplevel && toplevel.activated ? (toplevel.appId ?? "") : ""
    readonly property bool fullscreen: fakeFocus ? (fakeApp !== "" && fakeFullscreen)
        : (toplevel?.activated ?? false) && (toplevel?.fullscreen ?? false)

    // A player of the focused app playing (Brave's player is "brave…").
    function sameApp(player, app) {
        const a = app.toLowerCase();
        for (const name of [player.desktopEntry ?? "", player.identity ?? ""]) {
            const n = String(name).toLowerCase();
            if (n.length >= 3 && (n === a || a.includes(n) || n.includes(a)))
                return true;
        }
        return false;
    }
    readonly property bool playing: watching && focusedApp !== ""
        && Mpris.players.values.some(p => p.isPlaying && root.sameApp(p, root.focusedApp))

    // Away for sure: screen off (shell.qml binds Idle.screenOff), locked, asleep.
    property bool screenOff: false
    readonly property string marker: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-lock.secure"
    property bool markerThere: false
    readonly property bool locked: markerFile.path !== "" && markerThere
    readonly property bool asleep: Locker.sleeping
    readonly property bool away: locked || asleep || screenOff

    FileView {
        id: markerFile
        path: root.watching ? root.marker : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.markerThere = true
        onLoadFailed: root.markerThere = false
    }

    // No input for Style.screenTimeIdle s. Not held off by apps that keep
    // the screen awake ("Keep awake" too): the fullscreen / playing rule
    // above covers videos instead.
    property bool idle: false
    property real lastInput: Date.now()
    readonly property int idleSeconds: Math.max(10, Style.screenTimeIdle)
    IdleMonitor {
        id: idleAt
        enabled: root.watching && !root.fakeFocus
        timeout: root.idleSeconds
        respectInhibitors: false
        onIsIdleChanged: root.noteIdle(isIdle, root.idleSeconds)
    }

    // Idle (true: the last input was `secondsAgo` s ago) or back.
    function noteIdle(isIdle, secondsAgo) {
        const now = Date.now();
        if (isIdle === idle)
            return;
        if (isIdle) {
            lastInput = now - Math.max(0, secondsAgo ?? idleSeconds) * 1000;
            // Not held: the stretch ends at the last input.
            if (!held)
                closeAt(Math.max(segStart, lastInput));
        } else {
            lastInput = now;
        }
        idle = isIdle;
    }

    readonly property bool held: fullscreen || playing
    // The app counting now ("" = none).
    readonly property string current: watching && !away && (!idle || held) ? focusedApp : ""
    // Here and using the screen (Breaks reads this).
    readonly property bool inUse: current !== ""

    // Saved a moment after counting stops (idle, lock, no window); while it
    // counts, the minute tick saves.
    onCurrentChanged: {
        settle(Date.now());
        if (current === "")
            saveSoon.restart();
    }

    // ---- The stretch counting now --------------------------------------------------------
    property string segApp: ""
    property real segStart: 0
    // The last moment seen awake: the stretch's start, then each minute tick.
    property real lastTick: 0
    // A tick later than this after the one before: the laptop slept (or the
    // shell was stopped); the time between doesn't count.
    readonly property real maxGap: flusher.interval * 2 + 30000

    function settle(at) {
        if (current === segApp)
            return;
        closeAt(at);
        if (current !== "") {
            segApp = current;
            segStart = at;
            lastTick = at;
        }
    }

    function closeAt(at) {
        if (segApp === "")
            return;
        const end = at - lastTick > maxGap ? lastTick : at;
        add(segApp, segStart, Math.max(segStart, end));
        segApp = "";
    }

    function add(app, from, to) {
        if (!enabled || !(to > from))
            return;
        Count.credit(days, app, from, to);
        dirty = true;
        today = Count.dayKey(to);
        revision++;
    }

    // Once a minute while one counts: into the day, and saved. (On
    // `current`, not the stretch: a switch from one app to the next doesn't
    // start the minute over.)
    Timer {
        id: flusher
        interval: (Number(Quickshell.env("MINE_SCREENTIME_FLUSH")) || 60) * 1000
        repeat: true
        running: root.current !== ""
        onTriggered: root.tick(Date.now())
    }
    property int ticks: 0
    function tick(now) {
        ticks++;
        if (segApp !== "") {
            if (now - lastTick > maxGap || now < lastTick) {
                // Slept (or the clock went back): up to the last tick only,
                // and a new stretch from now.
                const app = segApp;
                console.log("screen time: a gap of", Math.round((now - lastTick) / 1000), "s, not counted");
                closeAt(lastTick);
                segApp = app;
                segStart = now;
            } else {
                add(segApp, segStart, now);
                segStart = now;
            }
            lastTick = now;
        }
        save();
    }

    // Everything so far into the file now (shutdown, log out, lock).
    function flush(why) {
        if (segApp !== "")
            tick(Date.now());
        else
            save();
        if (why)
            console.log("screen time: saved (" + why + ")");
    }

    // A new day for the popup's "today", also while nothing counts.
    property string today: Count.dayKey(Date.now())
    Timer {
        id: midnight
        running: root.watching
        interval: Math.max(1000, Count.nextMidnight(Date.now()) - Date.now() + 500)
        onTriggered: {
            root.tick(Date.now());
            root.today = Count.dayKey(Date.now());
            interval = Math.max(1000, Count.nextMidnight(Date.now()) - Date.now() + 500);
            restart();
        }
    }

    // ---- The days ------------------------------------------------------------------------------
    property var days: ({})
    // Goes up whenever `days` changes (it's changed in place).
    property int revision: 0
    property bool dirty: false
    property bool loadedOnce: false
    property int saves: 0
    readonly property int keepDays: Math.max(7, Style.screenTimeDays)

    function save() {
        if (!dirty || !loadedOnce)
            return;
        dirty = false;
        if (Count.trim(days, keepDays, Date.now()) > 0)
            revision++;
        file.save(Count.serialize(days));
    }
    Timer {
        id: saveSoon
        interval: 3000
        onTriggered: root.save()
    }

    StateFile {
        id: file
        path: root.statePath
        onLoaded: text => {
            const saved = text === "" ? {} : Count.parse(text);
            if (saved === null)
                console.warn("screen time:", root.statePath, "isn't JSON; starting over (the next save replaces it)");
            // What was counted before the file came in goes on top.
            root.days = Count.merge(saved ?? {}, root.days);
            root.finishLoad();
        }
        onRefused: why => {
            console.warn("screen time:", root.statePath, "is", why + ", not read; the next save puts a real file there");
            root.finishLoad();
        }
        onSaved: ok => {
            root.saves++;
            if (!ok)
                console.warn("screen time: couldn't save", root.statePath);
        }
    }
    function finishLoad() {
        loadedOnce = true;
        Count.trim(days, keepDays, Date.now());
        revision++;
        save();
    }
    Component.onCompleted: if (enabled) file.load()
    onEnabledChanged: {
        if (enabled && !loadedOnce)
            file.load();
    }

    // ---- For the popup, the tile and the bar item ------------------------------------------
    // Seconds counted right now, not in `days` yet (up to `now`, ms).
    function liveSeconds(now) {
        return segApp !== "" && enabled ? Math.max(0, Math.min(now, segStart + maxGap) - segStart) / 1000 : 0;
    }

    // One day's apps, most used first: [{ appId, seconds }] (today: with
    // what's counting now). Reads `revision`, so a binding using it follows.
    function appsOn(key, now) {
        const r = revision;
        const live = key === Count.dayKey(now) && segApp !== "" && Count.dayKey(segStart) === key;
        return Count.appsOf(days[key], live ? segApp : "", live ? liveSeconds(now) : 0);
    }
    function totalOn(key, now) {
        return Count.total(appsOn(key, now));
    }
    // The last seven days, oldest first: [{ key, label, seconds }].
    function week(now) {
        const out = [];
        for (let back = 6; back >= 0; back--) {
            const key = Count.dayBefore(now, back);
            out.push({ key: key, label: back === 0 ? "Today" : Count.weekdayOf(key), seconds: totalOn(key, now) });
        }
        return out;
    }
    function durationText(seconds, short) {
        return Count.durationText(seconds, short);
    }
    function dayKey(ms) {
        return Count.dayKey(ms);
    }

    // An app's name and icon, from its desktop entry.
    function appName(appId) {
        const entry = DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId);
        return entry?.name || appId;
    }
    function appIcon(appId) {
        return MangoClients.iconFor(appId);
    }

    // qs -c mine ipc call screentime status
    function status() {
        const now = Date.now();
        const today = appsOn(Count.dayKey(now), now);
        return JSON.stringify({
            enabled: enabled,
            counting: current,
            idle: idle,
            locked: locked,
            asleep: asleep,
            screenOff: screenOff,
            today: { seconds: Math.round(Count.total(today)), apps: today.map(a => ({ app: a.appId, seconds: Math.round(a.seconds) })) },
            week: week(now).map(d => ({ day: d.key, seconds: Math.round(d.seconds) }))
        });
    }
}
