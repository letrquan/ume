pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Locking, while the shell runs (Noctalia did this before; `mine on` turns
// its lock off so the two never race):
//  - before the laptop sleeps (lid closed, suspend): lock, and only let it
//    sleep once the lock screen is really up;
//  - when something asks the session to lock (`loginctl lock-session`): lock.
// The lock screen is ~/.local/bin/qs-lock: it does nothing when already
// locked, and returns once the lock is up (or after 4 s).
//
// How: a "delay" sleep inhibitor (systemd-inhibit … cat) is held all the
// time. When logind announces sleep (PrepareForSleep true) we lock, then let
// go of the inhibitor; logind waits for that (up to InhibitDelayMaxSec, 5 s
// by default). After waking up we take it again. All processes are the
// shell's own children, so they end with it.
// (Not hypridle: mango lacks the protocol hypridle needs to know the lock is
// up, so it can't hold sleep until then.)
//
// The same listener also passes on "the system is going down" (logind's
// PrepareForShutdown) as shutdown(): shell.qml hands it to
// services/AppRestore.qml, which then keeps its list of open apps. So it
// also runs, without locking anything, while only that is on.
//
// Tests: MINE_LOCKER_OFF=1 (off), MINE_LOCK_CMD (instead of qs-lock),
// MINE_LOGIND_MONITOR (a command printing gdbus-monitor-style lines).
Singleton {
    id: root

    readonly property bool enabled: Style.lockBeforeSleep && Quickshell.env("MINE_LOCKER_OFF") !== "1"
    readonly property bool listening: (enabled || Style.restoreApps) && Quickshell.env("MINE_LOCKER_OFF") !== "1"
    readonly property string lockCmd: Quickshell.env("MINE_LOCK_CMD") || (Quickshell.env("HOME") + "/.local/bin/qs-lock")
    readonly property string fakeMonitor: Quickshell.env("MINE_LOGIND_MONITOR") || ""
    // Our logind session's object path, to react only to its Lock signal.
    property string session: ""
    // Between "about to sleep" and "woke up".
    property bool sleeping: false
    readonly property bool holding: hold.running

    function takeHold() {
        if (enabled && !sleeping && !hold.running)
            hold.running = true;
    }
    function releaseHold() {
        safety.stop();
        hold.running = false;
    }

    // Reboot or power off coming (true), or called off (false).
    signal shutdown(bool going)

    function signal(line) {
        if (line.includes("PrepareForShutdown (true")) {
            shutdown(true);
            return;
        }
        if (line.includes("PrepareForShutdown (false")) {
            shutdown(false);
            return;
        }
        if (!enabled)
            return;
        if (line.includes("PrepareForSleep (true")) {
            sleeping = true;
            safety.restart();
            locking.running = true;
        } else if (line.includes("PrepareForSleep (false")) {
            sleeping = false;
            takeHold();
        } else if (line.includes("Session.Lock ()") && session !== "" && line.startsWith(session + ":")) {
            Quickshell.execDetached([lockCmd]);
        }
    }

    onEnabledChanged: {
        if (enabled) {
            takeHold();
        } else {
            releaseHold();
        }
    }
    Component.onCompleted: takeHold()

    // The inhibitor. `cat` waits on stdin, which closes when we stop it.
    Process {
        id: hold
        stdinEnabled: true
        command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=mine shell", "--why=Lock before sleep", "cat"]
        onExited: if (root.enabled && !root.sleeping) reHold.start()
    }
    Timer {
        id: reHold
        interval: 1000
        onTriggered: root.takeHold()
    }

    // Lock, then let the system sleep.
    Process {
        id: locking
        command: [root.lockCmd]
        onExited: root.releaseHold()
    }
    // Never keep the system awake on a stuck lock (logind gives up at 5 s).
    Timer {
        id: safety
        interval: 4500
        onTriggered: root.releaseHold()
    }

    // logind's signals: sleep coming / woke up, and our session's Lock.
    Process {
        id: monitor
        running: root.listening
        command: root.fakeMonitor !== ""
            ? ["sh", "-c", root.fakeMonitor]
            : ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser {
            onRead: line => root.signal(line)
        }
        onExited: if (root.listening) reMonitor.start()
    }
    Timer {
        id: reMonitor
        interval: 2000
        onTriggered: if (root.listening) monitor.running = true
    }

    Process {
        running: root.enabled
        command: ["busctl", "--system", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
                  "org.freedesktop.login1.Manager", "GetSessionByPID", "u", String(Quickshell.processId)]
        stdout: StdioCollector {
            onStreamFinished: root.session = (text.trim().split(" ")[1] ?? "").replace(/"/g, "")
        }
    }
}
