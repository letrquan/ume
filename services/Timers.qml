pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "../common/sounds.js" as SoundFiles

// A timer, a stopwatch and alarms: the control center's Timer, Stopwatch
// and Alarm tiles and their page (control/TimersPage.qml), the bar's
// "Timer" item (bar/TimerItem.qml), qs -c mine ipc call timers …
//   timer      a preset (1, 3, 5, 10, 15, 25 min) or any length; pause,
//              go on, cancel
//   stopwatch  start, pause, lap, reset
//   alarms     HH:MM, once or on chosen days, with a label; on and off
// When a timer ends or an alarm's time comes: a notification with Stop
// (an alarm also has Snooze: Style.timersSnoozeMinutes) and the alarm sound
// over and over until Stop, at most Style.timersRingSeconds. Closing the
// notification stops it too. Style.timersRingInSilent: it rings in Silent
// as well (the notification is urgent, so it pops up anyway); off, Silent
// keeps it quiet and the notification goes to the list.
// The focus timer (services/FocusTimer.qml) is its own thing, next to this.
//
// Everything is kept as wall-clock times in
// ~/.local/state/mine-shell/timers.json, so a running timer, the stopwatch
// and the alarms carry on over a restart and over sleep. The shell can't
// wake the laptop: a time that came while it slept (or while the shell
// wasn't running) isn't rung late; "Missed alarm at 07:00" says so instead
// (more than `lateMax` late counts as missed).
// Nothing ticks while nothing runs: one single-shot timer waits for the
// next time due (at most a minute, then it looks again).
//
// MINE_TIMERS_DRYRUN=1 (tests): the sound is only printed (notifications
// still go to the session's notification server), and shift(ms) moves the
// clock seen here (a fake sleep); MINE_TIMERS_TEST=1: shift() with the real
// sound command (a test's fake pw-play); MINE_TIMERS_SCALE: lengths run that
// many times faster (a 5 min timer, the snooze, the ring);
// MINE_TIMERS_STATE: another state file.
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_TIMERS_DRYRUN") === "1"
    readonly property real timeScale: Math.max(0.001, Number(Quickshell.env("MINE_TIMERS_SCALE")) || 1)
    readonly property string statePath: Quickshell.env("MINE_TIMERS_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/timers.json")

    readonly property var presets: [1, 3, 5, 10, 15, 25]       // minutes, the page's buttons
    // The page's tab (each tile's arrow opens its own): timer | stopwatch | alarms.
    property string pageTab: "timer"
    readonly property real minute: 60000 / timeScale            // ms
    // Later than this when it's seen: the laptop was asleep (or the shell
    // off) then, so it's missed, not rung.
    readonly property real lateMax: Math.max(2000, 90000 / timeScale)

    // ---- The clock ----------------------------------------------------------------
    // Wall-clock ms. shift(): tests only.
    property real skew: 0
    function now() {
        return Date.now() + skew;
    }
    function shift(ms) {
        if (!dryRun && Quickshell.env("MINE_TIMERS_TEST") !== "1")
            return "only with MINE_TIMERS_DRYRUN=1 (or MINE_TIMERS_TEST=1)";
        skew += Number(ms) || 0;
        check();
        return "ok";
    }
    // What the tiles, the page and the bar show the time from: on every
    // second while something counts, still otherwise.
    property real clock: now()
    readonly property bool counting: timerState === "running" || swRunning || ringing
    Timer {
        interval: 1000
        repeat: true
        running: root.counting
        triggeredOnStart: true
        onTriggered: root.clock = root.now()
    }

    // ---- Timer ----------------------------------------------------------------------
    property string timerState: "idle"      // idle | running | paused
    property real timerTotal: 0             // ms, as started
    property real timerEndsAt: 0            // wall-clock, while running
    property real timerLeftPaused: 0        // ms, while paused
    readonly property real timerLeft: timerState === "running" ? Math.max(0, timerEndsAt - clock)
                                    : timerState === "paused" ? timerLeftPaused : 0
    readonly property real timerProgress: timerTotal > 0 && timerState !== "idle" ? 1 - timerLeft / timerTotal : 0
    readonly property string timerText: clockText(Math.ceil(timerLeft / 1000))
    // The length last started (Again, and the page's custom field).
    property real lastLength: 5 * minute

    function startTimer(ms) {
        const length = Math.round(Number(ms));
        if (!(length >= 1000) || length > 24 * 3600000)
            return false;
        if (ringing && ringKind === "timer")
            stopRing();
        timerTotal = length;
        lastLength = length;
        timerEndsAt = now() + length;
        timerState = "running";
        changed();
        return true;
    }
    function startMinutes(m) {
        return startTimer(Number(m) * minute);
    }
    function pauseTimer() {
        if (timerState !== "running")
            return;
        timerLeftPaused = Math.max(0, timerEndsAt - now());
        timerState = "paused";
        changed();
    }
    function resumeTimer() {
        if (timerState !== "paused")
            return;
        timerEndsAt = now() + timerLeftPaused;
        timerState = "running";
        changed();
    }
    function toggleTimer() {
        if (timerState === "running")
            pauseTimer();
        else if (timerState === "paused")
            resumeTimer();
        else
            startTimer(lastLength);
    }
    function cancelTimer() {
        timerState = "idle";
        timerEndsAt = 0;
        timerLeftPaused = 0;
        changed();
    }
    // A minute more, running or just rung.
    function addMinute() {
        if (timerState === "running") {
            timerEndsAt += minute;
            timerTotal += minute;
            changed();
        } else if (timerState === "paused") {
            timerLeftPaused += minute;
            timerTotal += minute;
            changed();
        } else {
            startTimer(minute);
        }
    }

    // "4:59", "1:02:03".
    function clockText(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60;
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : String(m)) + ":" + String(r).padStart(2, "0");
    }
    // "5 min", "1 h 30 min", "45 s" (a length, for words).
    function lengthText(ms) {
        const s = Math.round(ms * timeScale / 1000);
        if (s < 60)
            return s + " s";
        const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60);
        return h > 0 ? h + " h" + (m > 0 ? " " + m + " min" : "") : m + " min";
    }
    // What the page's field takes: "5", "90" (minutes), "1:30" (min:s),
    // "1:30:00", "1h 30m", "45s" -> ms (real ones, scaled), or 0.
    function parseLength(text) {
        const t = String(text).trim().toLowerCase();
        let s = 0;
        let m;
        if ((m = t.match(/^(\d+(?:[.,]\d+)?)$/)))
            s = parseFloat(m[1].replace(",", ".")) * 60;
        else if ((m = t.match(/^(\d+):(\d{1,2})$/)))
            s = Number(m[1]) * 60 + Number(m[2]);
        else if ((m = t.match(/^(\d+):(\d{1,2}):(\d{1,2})$/)))
            s = Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]);
        else if ((m = t.match(/^(?:(\d+)\s*h)?\s*(?:(\d+)\s*m(?:in)?)?\s*(?:(\d+)\s*s)?$/)) && t !== "")
            s = Number(m[1] ?? 0) * 3600 + Number(m[2] ?? 0) * 60 + Number(m[3] ?? 0);
        return s > 0 && s <= 24 * 3600 ? s * 1000 / timeScale : 0;
    }

    // ---- Stopwatch ----------------------------------------------------------------
    property bool swRunning: false
    property real swSince: 0                // wall-clock of the last start
    property real swBase: 0                 // ms counted before it
    property var swLaps: []                 // the total at each lap, ms (newest last)
    readonly property bool swStarted: swRunning || swBase > 0
    function swElapsed(at) {
        return swBase + (swRunning ? Math.max(0, at - swSince) : 0);
    }
    readonly property string swText: clockText(swElapsed(clock) / 1000)

    function toggleStopwatch() {
        if (swRunning) {
            swBase = swElapsed(now());
            swRunning = false;
        } else {
            swSince = now();
            swRunning = true;
        }
        changed();
    }
    function lap() {
        if (!swRunning)
            return;
        swLaps = swLaps.concat([swElapsed(now())]).slice(-99);
        changed();
    }
    function resetStopwatch() {
        swRunning = false;
        swBase = 0;
        swSince = 0;
        swLaps = [];
        changed();
    }

    // ---- Alarms -------------------------------------------------------------------
    // [{ id, time: "07:00", days: [1..5] (0 = Sunday; none = once), label,
    //    on, next (wall-clock ms of its next time), snooze (wall-clock ms, 0) }]
    property var alarms: []
    readonly property var dayLetters: ["S", "M", "T", "W", "T", "F", "S"]
    readonly property var dayNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // The next one on: { alarm, at } or null.
    readonly property var nextAlarm: {
        let best = null;
        for (const a of alarms) {
            const at = a.snooze > 0 ? a.snooze : a.next;
            if (a.on && at > 0 && (best === null || at < best.at))
                best = { alarm: a, at: at };
        }
        return best;
    }

    function validTime(t) {
        return /^([01]?\d|2[0-3]):[0-5]\d$/.test(String(t).trim());
    }
    function normTime(t) {
        const [h, m] = String(t).trim().split(":");
        return String(Number(h)).padStart(2, "0") + ":" + m;
    }

    // The next time `alarm` goes off after `from` (wall-clock ms), or 0.
    function nextFire(alarm, from) {
        if (!validTime(alarm.time))
            return 0;
        const [h, m] = alarm.time.split(":").map(Number);
        const days = alarm.days ?? [];
        for (let d = 0; d <= 7; d++) {
            const at = new Date(from);
            at.setDate(at.getDate() + d);
            at.setHours(h, m, 0, 0);
            if (at.getTime() > from && (days.length === 0 || days.includes(at.getDay())))
                return at.getTime();
        }
        return 0;
    }

    function addAlarm(time, days, label) {
        if (!validTime(time))
            return "";
        const a = { id: "a" + Date.now().toString(36) + Math.floor(Math.random() * 1000), time: normTime(time),
                    days: (days ?? []).filter(d => d >= 0 && d <= 6).sort(), label: String(label ?? "").trim().slice(0, 80),
                    on: true, next: 0, snooze: 0 };
        a.next = nextFire(a, now());
        alarms = alarms.concat([a]).sort((x, y) => x.time.localeCompare(y.time));
        changed();
        return a.id;
    }
    function updateAlarm(id, fields) {
        alarms = alarms.map(a => {
            if (a.id !== id)
                return a;
            const b = Object.assign({}, a, fields);
            if (fields.time !== undefined) {
                if (!validTime(fields.time))
                    return a;
                b.time = normTime(fields.time);
            }
            if (fields.days !== undefined)
                b.days = fields.days.filter(d => d >= 0 && d <= 6).sort();
            if (fields.label !== undefined)
                b.label = String(fields.label).trim().slice(0, 80);
            // Turned on, or its time or days changed: from now on.
            b.snooze = 0;
            b.next = b.on ? nextFire(b, now()) : 0;
            return b;
        }).sort((x, y) => x.time.localeCompare(y.time));
        changed();
    }
    function setAlarmOn(id, on) {
        updateAlarm(id, { on: on });
    }
    function toggleAlarm(id) {
        const a = alarms.find(x => x.id === id);
        if (a)
            setAlarmOn(id, !a.on);
    }
    function removeAlarm(id) {
        if (ringing && ringKind === "alarm" && ringId === id)
            stopRing();
        alarms = alarms.filter(a => a.id !== id);
        changed();
    }
    function toggleDay(id, day) {
        const a = alarms.find(x => x.id === id);
        if (!a)
            return;
        updateAlarm(id, { days: a.days.includes(day) ? a.days.filter(d => d !== day) : a.days.concat([day]) });
    }

    // "Mon–Fri", "Every day", "Weekends", "Tue, Thu", "Once".
    function daysText(days) {
        const d = (days ?? []).slice().sort();
        if (d.length === 0)
            return "Once";
        if (d.length === 7)
            return "Every day";
        if (d.join() === "1,2,3,4,5")
            return "Mon–Fri";
        if (d.join() === "0,6")
            return "Weekends";
        return d.map(i => dayNames[i]).join(", ");
    }
    // "07:00", or "Mon 07:00" when not today.
    function whenText(at) {
        const d = new Date(at), today = new Date(now());
        const hm = Qt.formatTime(d, "HH:mm");
        return d.toDateString() === today.toDateString() ? hm : dayNames[d.getDay()] + " " + hm;
    }

    // ---- Due times ------------------------------------------------------------------
    // Everything that is due is looked at, then the timer waits for the
    // next one (at most a minute: after sleep the clock has jumped, and the
    // look a minute later sees it).
    function check() {
        if (!loaded)
            return;
        const t = now();
        clock = t;
        if (timerState === "running" && t >= timerEndsAt) {
            const late = t - timerEndsAt;
            const length = timerTotal;
            const endedAt = timerEndsAt;
            timerState = "idle";
            timerEndsAt = 0;
            changed();
            if (late <= lateMax)
                ring("timer", "timer", "Timer done", lengthText(length) + " timer");
            else
                missed("Missed timer at " + whenText(endedAt), lengthText(length) + " timer · it ended while the laptop was asleep or the shell wasn't running");
        }
        let any = false;
        const list = alarms.map(a => {
            if (!a.on)
                return a;
            const snoozed = a.snooze > 0;
            const at = snoozed ? a.snooze : a.next;
            if (!(at > 0) || t < at)
                return a;
            any = true;
            const b = Object.assign({}, a, { snooze: 0 });
            if (!snoozed || b.days.length === 0) {
                // Once: off now; on days: its next day.
                b.next = b.days.length === 0 ? 0 : nextFire(b, t);
                b.on = b.days.length > 0;
            }
            if (t - at <= lateMax)
                ring("alarm", b.id, b.label !== "" ? b.label : "Alarm", b.time + (snoozed ? " · snoozed" : ""));
            else
                missed("Missed alarm at " + whenText(at), (b.label !== "" ? b.label + " · " : "") + "the laptop was asleep or the shell wasn't running");
            return b;
        });
        if (any) {
            alarms = list;
            changed();
        }
        if (ringing && t >= ringUntil)
            quiet();
        schedule();
    }

    function schedule() {
        const t = now();
        let soonest = Infinity;
        if (timerState === "running")
            soonest = Math.min(soonest, timerEndsAt);
        for (const a of alarms) {
            const at = a.snooze > 0 ? a.snooze : a.next;
            if (a.on && at > 0)
                soonest = Math.min(soonest, at);
        }
        if (ringing && sounding)
            soonest = Math.min(soonest, ringUntil);
        if (soonest === Infinity) {
            due.stop();
            return;
        }
        due.interval = Math.max(20, Math.min(60000, soonest - t + 5));
        due.restart();
    }
    Timer {
        id: due
        onTriggered: root.check()
    }

    // Woken up (services/Locker.qml): look at once, not up to a minute later.
    Connections {
        target: Locker
        function onSleepingChanged() {
            if (!Locker.sleeping)
                root.check();
        }
    }

    // ---- Ringing ----------------------------------------------------------------------
    property bool ringing: false            // its notification is up
    property bool sounding: false           // and the sound plays
    property string ringKind: ""            // timer | alarm
    property string ringId: ""              // the alarm's id
    property string ringTitle: ""
    property string ringBody: ""
    property real ringUntil: 0              // the sound stops by itself then
    readonly property real ringMs: Math.max(5, Style.timersRingSeconds) * 1000 / timeScale

    function ring(kind, id, title, body) {
        if (ringing)
            stopRing();
        ringing = true;
        ringKind = kind;
        ringId = id;
        ringTitle = title;
        ringBody = body;
        ringUntil = now() + ringMs;
        // Silent (by hand, its hours, a fullscreen app, a shared screen):
        // only with Style.timersRingInSilent.
        const hushed = Notifs.dnd || Notifs.fullscreenQuiet || Notifs.privacyQuiet;
        const loud = !hushed || Style.timersRingInSilent;
        // Urgent only to get through Silent (the shell shows urgent ones in
        // red); otherwise a plain one that stays until it's answered.
        notify(kind === "alarm", hushed && loud);
        if (loud)
            sound(true);
        changed();
    }

    // The sound ends (Stop, or it rang long enough); the notification stays
    // until Stop or it's closed.
    function quiet() {
        sound(false);
        changed();
    }

    // Stop: the sound and the notification.
    function stopRing() {
        if (!ringing)
            return;
        sound(false);
        note?.close();
        ringing = false;
        ringKind = "";
        ringId = "";
        changed();
    }

    function snooze() {
        if (!ringing || ringKind !== "alarm")
            return;
        const id = ringId;
        stopRing();
        alarms = alarms.map(a => a.id === id ? Object.assign({}, a, { on: true, snooze: now() + Style.timersSnoozeMinutes * minute }) : a);
        changed();
    }

    // The sound: one process per ring (a new ring never waits for the old
    // one to be gone), stopped with SIGTERM so the sound playing right then
    // ends too (common/sounds.js loopCommand).
    property var ringProc: null
    function sound(on) {
        if (on === sounding)
            return;
        sounding = on;
        if (on) {
            // The loop's own limit is a little past ringMs, which stops it first.
            const cmd = SoundFiles.loopCommand("alarm", Style.timersVolume, Math.max(5, Style.timersRingSeconds) + 5);
            if (dryRun)
                console.log("timers (dry run): ring", JSON.stringify(cmd));
            ringProc = ringMaker.createObject(root, {
                command: dryRun ? ["sh", "-c", "trap 'exit 0' TERM INT; while :; do sleep 0.2; done"] : cmd
            });
        } else {
            if (dryRun)
                console.log("timers (dry run): ring stops");
            ringProc?.stop();
            ringProc = null;
        }
    }
    Component {
        id: ringMaker

        Process {
            id: ringer
            running: true
            function stop() {
                if (running)
                    signal(15);
            }
            onExited: {
                // It stopped on its own (no sound file, no pw-play).
                if (root.ringProc === ringer) {
                    root.ringProc = null;
                    root.sounding = false;
                }
                ringer.destroy();
            }
        }
    }

    // The notification: Stop (and Snooze, or Again for a timer); it stays
    // until answered (-t 0), and is urgent in Silent (when it rings there) so
    // it pops up anyway. What's clicked comes
    // back on notify-send's stdout; closing it without a button stops the
    // ringing as well. One process per notification (`note` is the current
    // one): an old one still on its way out never touches the new ring.
    property var note: null
    function notify(alarm, urgent) {
        note?.close();
        note = noteMaker.createObject(root, { alarm: alarm, urgent: urgent, title: ringTitle, body: ringBody });
    }
    Component {
        id: noteMaker

        Scope {
            id: one

            property bool alarm: false
            property bool urgent: false
            property string title: ""
            property string body: ""
            property int nid: 0                 // the notification's id (notify-send -p)
            property bool closing: false
            readonly property bool current: root.note === one
            readonly property string app: alarm ? "Alarm" : "Timer"

            // Gone by the shell's own notification server (Notifs), or over
            // D-Bus when another one has them; killed if it still waits.
            function close() {
                if (closing)
                    return;
                closing = true;
                const e = Notifs.list.find(x => x.id === nid && x.appName === app && Notifs.live[x.key] !== undefined);
                if (nid > 0 && e)
                    Notifs.dismiss(e.key);
                else if (nid > 0)
                    Quickshell.execDetached(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                                             "--object-path", "/org/freedesktop/Notifications",
                                             "--method", "org.freedesktop.Notifications.CloseNotification", String(nid)]);
                giveUp.start();
            }

            Timer {
                id: giveUp
                interval: 3000
                onTriggered: if (sender.running) sender.signal(15)
            }

            Process {
                id: sender
                running: true
                command: ["notify-send", "-a", one.app, "-i", "alarm-symbolic", "-u", one.urgent ? "critical" : "normal", "-t", "0", "-p",
                          "-h", "boolean:suppress-sound:true"]
                    .concat(one.alarm ? ["-A", "snooze=Snooze " + Style.timersSnoozeMinutes + " min"] : ["-A", "again=Again"])
                    .concat(["-A", "stop=Stop", "--", one.title, one.body])
                stdout: SplitParser {
                    onRead: line => {
                        const t = line.trim();
                        if (one.nid === 0 && /^\d+$/.test(t)) {
                            one.nid = Number(t);
                            return;
                        }
                        if (!one.current || one.closing)
                            return;
                        if (t === "snooze") {
                            root.snooze();
                        } else if (t === "again") {
                            const length = root.lastLength;
                            root.stopRing();
                            root.startTimer(length);
                        } else if (t === "stop" || t === "default") {
                            root.stopRing();
                        }
                    }
                }
                onExited: {
                    // Closed without a button (dismissed, or it went away): stop.
                    if (one.current && !one.closing && root.ringing)
                        root.stopRing();
                    if (root.note === one)
                        root.note = null;
                    one.destroy();
                }
            }
        }
    }

    function missed(summary, body) {
        const cmd = ["notify-send", "-a", "Alarm", "-i", "alarm-symbolic", "--", summary, body];
        console.log("timers:", summary);
        Quickshell.execDetached(cmd);
    }

    // ---- Kept ---------------------------------------------------------------------------
    property bool loaded: false

    function changed() {
        if (!loaded)
            return;
        store.save(JSON.stringify({
            timer: { state: timerState, total: timerTotal, endsAt: timerEndsAt, left: timerLeftPaused, last: lastLength },
            stopwatch: { running: swRunning, since: swSince, base: swBase, laps: swLaps },
            alarms: alarms,
            ring: ringing ? { kind: ringKind, id: ringId, title: ringTitle, body: ringBody, until: ringUntil, sounding: sounding } : null
        }, null, 1) + "\n");
        schedule();
    }

    function read(text) {
        let d = {};
        try {
            d = text.trim() === "" ? {} : JSON.parse(text);
        } catch (e) {
            console.warn("timers: can't read", statePath, "- starting empty");
        }
        const num = v => typeof v === "number" && isFinite(v) ? v : 0;
        const tm = d.timer ?? {};
        timerState = ["running", "paused"].includes(tm.state) ? tm.state : "idle";
        timerTotal = num(tm.total);
        timerEndsAt = num(tm.endsAt);
        timerLeftPaused = num(tm.left);
        lastLength = num(tm.last) > 0 ? num(tm.last) : 5 * minute;
        const sw = d.stopwatch ?? {};
        swRunning = sw.running === true;
        swSince = num(sw.since);
        swBase = num(sw.base);
        swLaps = Array.isArray(sw.laps) ? sw.laps.filter(v => typeof v === "number") : [];
        alarms = (Array.isArray(d.alarms) ? d.alarms : [])
            .filter(a => a && typeof a.id === "string" && validTime(a.time))
            .map(a => ({ id: a.id, time: normTime(a.time), days: Array.isArray(a.days) ? a.days.filter(x => x >= 0 && x <= 6) : [],
                         label: typeof a.label === "string" ? a.label : "", on: a.on === true, next: num(a.next), snooze: num(a.snooze) }));
        loaded = true;
        // Rang when the shell stopped: on again until its time is up.
        const r = d.ring;
        if (r && num(r.until) > now() && ["timer", "alarm"].includes(r.kind)) {
            ringTitle = String(r.title ?? "");
            ringBody = String(r.body ?? "");
            ringing = true;
            ringKind = r.kind;
            ringId = String(r.id ?? "");
            ringUntil = num(r.until);
            notify(r.kind === "alarm", Notifs.dnd || Notifs.fullscreenQuiet || Notifs.privacyQuiet);
            if (r.sounding)
                sound(true);
        }
        // Times that went by while the shell wasn't running are missed now.
        check();
    }

    StateStore {
        id: store
        path: root.statePath
        onLoaded: text => root.read(text)
    }
    Component.onCompleted: store.load()

    // For `qs -c mine ipc call timers status`.
    function status() {
        return JSON.stringify({
            timer: { state: timerState, left: Math.round(timerLeft), total: timerTotal, endsAt: timerEndsAt },
            stopwatch: { running: swRunning, elapsed: Math.round(swElapsed(now())), laps: swLaps },
            alarms: alarms,
            ringing: ringing, sounding: sounding, ringKind: ringKind, ringTitle: ringTitle
        });
    }
}
