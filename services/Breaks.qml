pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common

// Break reminders. After Style.breakAfter minutes on the screen without a
// real break, a gentle notification: "Time for a break · On for 50 min",
// with Snooze (Style.breakSnooze min) and Take a break. Take a break shows
// a short countdown on the screen (control/BreakWindow.qml,
// Style.breakLength min); it's done when you come back after it (or when
// it ends while you're still there). Not taken: the next one comes after
// another Style.breakAfter minutes.
//
// A real break: away for Style.breakResetAfter minutes or more: no input
// (apps keeping the screen awake hold that off: a film isn't a break), the
// lock screen, sleep or the screen off (services/ScreenTime.qml knows
// those). Shorter pauses don't count, nor do they stop the clock.
//
// Quiet while you're busy with something on screen: a fullscreen window
// (a film, slides, a game), the screen shared or recorded
// (services/Privacy.qml, Recorder), or Silent. A reminder due then waits
// until that's over.
//
// Optional (Style.breakEyes, off by default): the 20-20-20 rule, every
// Style.breakEyesEvery minutes on the screen, a short "Look away" (20
// seconds at something 6 m away).
//
// MINE_BREAKS_SECONDS (tests): one "minute" lasts this many seconds;
// MINE_BREAKS_DRYRUN=1: notifications are only printed. Away by input
// comes from noteIdle() too (the tests have no compositor).
Singleton {
    id: root

    readonly property bool enabled: Style.breakReminders
    readonly property bool eyes: Style.breakEyes
    readonly property bool dryRun: Quickshell.env("MINE_BREAKS_DRYRUN") === "1"
    readonly property real minute: (Number(Quickshell.env("MINE_BREAKS_SECONDS")) || 60) * 1000
    readonly property bool watching: enabled || eyes

    readonly property real afterMs: Math.max(1, Style.breakAfter) * minute
    readonly property real resetMs: Math.max(1, Style.breakResetAfter) * minute
    readonly property real snoozeMs: Math.max(1, Style.breakSnooze) * minute
    readonly property real lengthMs: Math.max(1, Style.breakLength) * minute
    readonly property real eyesMs: Math.max(5, Style.breakEyesEvery) * minute

    // ---- Here or away ------------------------------------------------------------------------
    // No input for breakResetAfter: that alone is a real break. Held off by
    // inhibitors (a video playing), unlike screen time's own idle.
    property bool idle: false
    IdleMonitor {
        enabled: root.watching && !ScreenTime.fakeFocus
        timeout: Math.max(1, Math.round(root.resetMs / 1000))
        respectInhibitors: true
        onIsIdleChanged: root.noteIdle(isIdle)
    }
    function noteIdle(isIdle) {
        if (isIdle !== idle)
            idle = isIdle;
    }

    readonly property bool away: watching && (idle || ScreenTime.away)
    // Since when (0 = here). By input: since the last input.
    property real awaySince: 0
    onAwayChanged: {
        const now = Date.now();
        if (away) {
            awaySince = idle ? now - resetMs : now;
            due.stop();
            eyesDue.stop();
        } else {
            const gone = awaySince > 0 ? now - awaySince : 0;
            awaySince = 0;
            if (gone >= resetMs)
                tookBreak(now, minutesText(gone) + " away");
            else if (phase === "after")
                finishBreak(now);
            plan();
        }
    }

    // ---- The clock ---------------------------------------------------------------------------
    // On the screen since (the end of the last real break, or start).
    property real onSince: Date.now()
    // Snoozed until (0 = not).
    property real snoozedUntil: 0
    // Reminders since the last real break, and when the last one came (the
    // next one: another breakAfter after it).
    property int reminded: 0
    property real lastReminder: 0
    property real eyesSince: Date.now()
    // A reminder is due, waiting for the quiet to end.
    property bool waiting: false

    readonly property real nextAt: !enabled ? 0
        : snoozedUntil > 0 ? snoozedUntil : (lastReminder > 0 ? lastReminder : onSince) + afterMs

    readonly property bool quiet: Notifs.dnd || ScreenTime.fullscreen || Privacy.sharing || Recorder.recording
    onQuietChanged: {
        if (!quiet && waiting && !away) {
            waiting = false;
            remind();
        }
    }

    function tookBreak(now, why) {
        console.log("breaks: a real break (" + why + "), the clock starts over");
        onSince = now;
        eyesSince = now;
        snoozedUntil = 0;
        reminded = 0;
        lastReminder = 0;
        waiting = false;
        if (phase !== "work")
            endBreak();
    }

    // Set the timers for the next reminders (events, no ticking).
    function plan() {
        const now = Date.now();
        due.stop();
        eyesDue.stop();
        if (away)
            return;
        if (enabled && phase === "work") {
            due.interval = Math.max(50, nextAt - now);
            due.start();
        }
        if (eyes && phase === "work") {
            eyesDue.interval = Math.max(50, eyesSince + eyesMs - now);
            eyesDue.start();
        }
    }
    onNextAtChanged: plan()
    onEyesChanged: plan()
    onEyesMsChanged: plan()
    Component.onCompleted: plan()

    Timer {
        id: due
        onTriggered: {
            if (root.away || !root.enabled || root.phase !== "work")
                return;
            if (root.quiet) {
                root.waiting = true;
                console.log("breaks: a reminder is due, waiting for quiet to end");
                return;
            }
            root.remind();
        }
    }
    Timer {
        id: eyesDue
        onTriggered: {
            root.eyesSince = Date.now();
            if (!root.away && !root.quiet && root.phase === "work")
                root.notify("eyes", "Look away", "20 seconds at something 6 m (20 feet) away", false);
            root.plan();
        }
    }

    function minutesText(ms) {
        const m = Math.round(ms / minute);
        return m < 60 ? m + " min" : Math.floor(m / 60) + " h" + (m % 60 > 0 ? " " + (m % 60) + " min" : "");
    }

    function remind() {
        reminded++;
        lastReminder = Date.now();
        snoozedUntil = 0;
        notify("break", "Time for a break", "On for " + minutesText(Date.now() - onSince)
               + ". Look away, stretch, have some water.", true);
        plan();
    }

    // The notification (ours: Notifs shows it). Snooze / Take a break come
    // back from notify-send as the button's name.
    function notify(kind, summary, body, buttons) {
        const cmd = ["notify-send", "-a", "Screen time", "-i", kind === "eyes" ? "view-reveal-symbolic" : "alarm-symbolic"]
            .concat(buttons ? ["-A", "snooze=Snooze " + Style.breakSnooze + " min", "-A", "break=Take a break"] : ["-e"])
            .concat(["--", summary, body]);
        console.log("breaks:", kind, "|", body);
        if (dryRun) {
            console.log("breaks (dry run):", JSON.stringify(cmd));
            return;
        }
        notice.createObject(root).exec(cmd);
    }
    Component {
        id: notice

        Process {
            stdout: SplitParser {
                onRead: line => {
                    if (line === "snooze")
                        root.snooze();
                    else if (line === "break")
                        root.takeBreak();
                }
            }
            onExited: destroy()
        }
    }

    function snooze() {
        snoozedUntil = Date.now() + snoozeMs;
        console.log("breaks: snoozed for", Style.breakSnooze, "min");
        plan();
    }

    // ---- Taking one ---------------------------------------------------------------------------
    // work | break (the countdown) | after (it ended while you were away:
    // done when you're back).
    property string phase: "work"
    property real breakEndsAt: 0
    readonly property bool showing: phase !== "work"
    // Updated each second while the countdown shows (BreakWindow reads it).
    property real now: Date.now()
    readonly property real breakLeft: Math.max(0, breakEndsAt - now)

    function takeBreak() {
        if (phase !== "work")
            return;
        console.log("breaks: taking a break of", Style.breakLength, "min");
        waiting = false;
        breakEndsAt = Date.now() + lengthMs;
        now = Date.now();
        phase = "break";
        plan();
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.phase === "break"
        onTriggered: {
            root.now = Date.now();
            if (root.breakLeft > 0)
                return;
            // Over: done now if you're still here; else when you're back.
            if (root.away)
                root.phase = "after";
            else
                root.finishBreak(Date.now());
        }
    }
    // The countdown went by: as good as a real break.
    function finishBreak(at) {
        console.log("breaks: break done");
        tookBreak(at, "took one");
    }
    // Skip (or Esc) during the countdown: back to work, asked again in a bit.
    function skipBreak() {
        if (phase === "work")
            return;
        if (phase === "after") {
            finishBreak(Date.now());
            return;
        }
        console.log("breaks: break skipped");
        endBreak();
        snooze();
    }
    function endBreak() {
        phase = "work";
        breakEndsAt = 0;
        plan();
    }

    function setOn(on) {
        Settings.set("breakReminders", on);
    }

    // For the popup and IPC.
    readonly property string detail: !enabled ? "Off"
        : phase !== "work" ? "On a break"
        : away ? "Away"
        : waiting ? "Waiting for quiet"
        : "Every " + minutesText(afterMs)
    function status() {
        const now = Date.now();
        return JSON.stringify({
            enabled: enabled, eyes: eyes, phase: phase, away: away, quiet: quiet, waiting: waiting,
            onForMinutes: Math.round((now - onSince) / minute),
            nextInMinutes: enabled ? Math.max(0, Math.round((nextAt - now) / minute)) : -1,
            breakLeftSeconds: phase === "break" ? Math.round(breakLeft / 1000) : 0
        });
    }
}
