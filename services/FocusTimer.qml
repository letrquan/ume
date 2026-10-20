pragma Singleton
import QtQuick
import Quickshell
import qs.common

// A focus timer (pomodoro): Style.focusMinutes of work, then a short
// break (Style.focusBreak), and a long one (Style.focusLongBreak) after
// every Style.focusRounds rounds of work. It goes on by itself from one to
// the next and says so with a notification. Style.focusSilent: Silent is
// on while you work (and off again after, if it turned it on).
// The bar item (bar/FocusTimer.qml, "Focus timer" in Bar items): click to
// start / pause, right click to stop, scroll before starting to change the
// length. Also: qs -c mine ipc call focus toggle | reset | skip
// Only kept while the shell runs.
//
// MINE_FOCUS_DRYRUN=1 (tests): notifications are only printed;
// MINE_FOCUS_SECONDS: one "minute" lasts this many seconds.
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_FOCUS_DRYRUN") === "1"
    readonly property real minute: Number(Quickshell.env("MINE_FOCUS_SECONDS")) || 60

    property string phase: "idle"         // idle | focus | break | longbreak
    property bool paused: false
    readonly property bool active: phase !== "idle"
    readonly property bool running: active && !paused
    property int round: 0                 // rounds of work done since start

    // Scroll on the bar item before starting: this time only, 5-120 min.
    property int plannedMinutes: Style.focusMinutes
    function adjust(by) {
        if (!active)
            plannedMinutes = Math.max(5, Math.min(120, plannedMinutes + by));
    }

    property real total: 0                // seconds of this phase
    property real remaining: 0
    property real endsAt: 0               // ms since the epoch, while running
    readonly property real progress: total > 0 ? 1 - remaining / total : 0
    readonly property string timeText: {
        const s = Math.max(0, Math.ceil(remaining));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    readonly property string phaseLabel: phase === "focus" ? "Focus"
                                       : phase === "break" ? "Short break"
                                       : phase === "longbreak" ? "Long break" : "Focus timer"

    function minutesOf(p) {
        return p === "focus" ? plannedMinutes
             : p === "break" ? Style.focusBreak : Style.focusLongBreak;
    }

    function begin(p) {
        phase = p;
        paused = false;
        total = minutesOf(p) * minute;
        remaining = total;
        endsAt = Date.now() + total * 1000;
        // Silent comes on a moment later, so "Back to work" still shows.
        if (p === "focus") {
            silenceSoon.restart();
        } else {
            silenceSoon.stop();
            silent(false);
        }
    }
    Timer {
        id: silenceSoon
        interval: 1500
        onTriggered: if (root.phase === "focus") root.silent(true)
    }

    // Start, pause or go on.
    function toggle() {
        if (!active) {
            round = 0;
            begin("focus");
        } else if (paused) {
            paused = false;
            endsAt = Date.now() + remaining * 1000;
        } else {
            tick();
            paused = true;
        }
    }

    function reset() {
        phase = "idle";
        paused = false;
        round = 0;
        total = 0;
        remaining = 0;
        plannedMinutes = Style.focusMinutes;
        silenceSoon.stop();
        silent(false);
    }

    // Straight to the next part (work -> break, break -> work).
    function skip() {
        if (active)
            next();
    }

    function minutes(n) {
        return n === 1 ? "1 minute" : n + " minutes";
    }

    function next() {
        if (phase === "focus") {
            round++;
            const long = Style.focusRounds > 0 && round % Style.focusRounds === 0;
            begin(long ? "longbreak" : "break");
            notify(false, long ? "Long break" : "Break time",
                   minutes(minutesOf(phase)) + ". " + (long ? round + " rounds of work done, well done."
                                                         : "Round " + round + " done."));
        } else {
            begin("focus");
            notify(true, "Back to work", minutes(plannedMinutes) + " of focus.");
        }
    }

    function tick() {
        if (!running)
            return;
        remaining = Math.max(0, (endsAt - Date.now()) / 1000);
        if (remaining <= 0)
            next();
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: root.tick()
    }

    // ---- Silent while working (Style.focusSilent) ---------------------------------
    property bool silencedByUs: false
    function silent(on) {
        if (on && Style.focusSilent && !Notifs.dnd) {
            Notifs.toggleDnd();
            silencedByUs = true;
        } else if (!on && silencedByUs) {
            if (Notifs.dnd)
                Notifs.toggleDnd();
            silencedByUs = false;
        }
    }

    // The live activity says it (Style.activityFocus), else a notification.
    function notify(work, summary, body) {
        if (Activities.show({ kind: "focus", work: work, title: summary, detail: body.replace(/\.$/, "").replace(/\. /g, " · ") }))
            return;
        const cmd = ["notify-send", "-a", "Focus timer", "-i", "alarm-symbolic", summary, body];
        if (dryRun)
            console.log("focus (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // A new length in Settings shows up when not running.
    Connections {
        target: Style
        function onFocusMinutesChanged() {
            if (!root.active)
                root.plannedMinutes = Style.focusMinutes;
        }
    }
}
