pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.common
import "netqr.js" as NetQr

// Airplane mode (the control center's "airplane" tile): every radio off,
// then back to how they were.
//   on   first what's on now:  nmcli -t -f WIFI,WWAN radio  and
//        rfkill -rno TYPE,SOFT,HARD (+ whether BlueZ has the adapter
//        powered), saved to ~/.local/state/mine-shell/airplane.json; then
//        nmcli radio all off       NetworkManager's own switch (Wi-Fi and
//                                  mobile broadband), the one the Wi-Fi tile
//                                  flips, so it can bring Wi-Fi back on a plane
//        rfkill block bluetooth    BlueZ has no airplane switch; this is the
//                                  kernel's radio switch (as GNOME does it)
//   off  only what was on before: nmcli radio wifi on / wwan on, rfkill
//        unblock bluetooth and the adapter powered again if it was. With
//        nothing on before, Wi-Fi comes on (like a phone).
// Turning Wi-Fi or Bluetooth on from their own tiles (or elsewhere) while
// it's on ends airplane mode (nothing else changes).
//
// Tests: MINE_NMCLI and MINE_RFKILL (the commands to run),
// MINE_AIRPLANE_DRYRUN=1 (changes printed, not run; the reads still run),
// MINE_AIRPLANE_STATE.
Singleton {
    id: root

    readonly property string nmcli: Quickshell.env("MINE_NMCLI") || "nmcli"
    readonly property string rfkill: Quickshell.env("MINE_RFKILL") || "rfkill"
    readonly property bool dryRun: Quickshell.env("MINE_AIRPLANE_DRYRUN") === "1"
    readonly property string statePath: Quickshell.env("MINE_AIRPLANE_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/airplane.json")

    property bool on: false
    property string busy: ""            // "on" | "off" while switching
    property string error: ""
    // What was on before (restored by off).
    property var before: ({ wifi: false, wwan: false, btUnblocked: false, btPowered: false })

    readonly property string detail: busy === "on" ? "Turning on…"
        : busy === "off" ? "Turning off…"
        : error !== "" ? error
        : on ? "Wi-Fi and Bluetooth off"
        : "Off"

    function toggle() {
        setOn(!on);
    }

    function setOn(want) {
        if (busy !== "" || want === on)
            return;
        error = "";
        busy = want ? "on" : "off";
        if (want)
            turnOn();
        else
            turnOff();
    }

    function turnOn() {
        run([nmcli, "-t", "-f", "WIFI,WWAN", "radio"], (code, out) => {
            const nm = NetQr.rows(out, 2)[0] ?? ["", ""];
            run([rfkill, "-rno", "TYPE,SOFT,HARD"], (code2, out2) => {
                const bt = String(out2).split("\n").map(l => l.trim().split(/\s+/)).filter(f => f[0] === "bluetooth");
                const btUnblocked = bt.some(f => f[1] === "unblocked" && f[2] === "unblocked");
                const adapter = ControlState.adapter;
                before = {
                    wifi: nm[0] === "enabled",
                    wwan: nm[1] === "enabled",
                    btUnblocked: btUnblocked,
                    btPowered: btUnblocked && (adapter ? adapter.enabled === true : false)
                };
                on = true;
                saveState();
                change([[nmcli, "radio", "all", "off"], [rfkill, "block", "bluetooth"]], ok => {
                    busy = "";
                    watching.restart();
                });
            });
        });
    }

    function turnOff() {
        const b = before;
        const nothing = !b.wifi && !b.wwan && !b.btUnblocked;
        const steps = [];
        if (b.wifi || nothing)
            steps.push([nmcli, "radio", "wifi", "on"]);
        if (b.wwan)
            steps.push([nmcli, "radio", "wwan", "on"]);
        if (b.btUnblocked)
            steps.push([rfkill, "unblock", "bluetooth"]);
        on = false;
        saveState();
        change(steps, ok => {
            busy = "";
            // BlueZ sees the adapter again a moment after the unblock.
            if (b.btPowered)
                powerBack.restart();
        });
    }
    Timer {
        id: powerBack
        interval: 1500
        onTriggered: {
            if (ControlState.adapter && !ControlState.adapter.enabled)
                ControlState.setBluetooth(true);
        }
    }

    // On: Wi-Fi or Bluetooth turned on by hand ends it. Watching starts a
    // moment after our own changes have landed.
    Timer {
        id: watching
        interval: 3000
    }
    function noticed(what) {
        if (on && busy === "" && !watching.running) {
            console.log("airplane: " + what + " came on: airplane mode ends");
            on = false;
            saveState();
        }
    }
    Connections {
        target: Networking
        function onWifiEnabledChanged() {
            if (Networking.wifiEnabled)
                root.noticed("Wi-Fi");
        }
    }
    Connections {
        target: ControlState.adapter
        ignoreUnknownSignals: true
        function onEnabledChanged() {
            if (ControlState.adapter?.enabled)
                root.noticed("Bluetooth");
        }
    }

    // Changes in order; one failing doesn't stop the others (each radio
    // matters on its own), but the first failure is said.
    function change(steps, done) {
        let ok = true;
        const next = i => {
            if (i >= steps.length) {
                done(ok);
                return;
            }
            const cmd = steps[i];
            if (dryRun) {
                console.log("airplane (dry run): " + cmd.join(" "));
                Qt.callLater(() => next(i + 1));
                return;
            }
            console.log("airplane: " + cmd.join(" "));
            run(cmd, (code, out, err) => {
                if (code !== 0) {
                    if (ok)
                        error = firstLine(err) || cmd[0] + " failed (" + code + ")";
                    ok = false;
                    console.log("airplane: failed:", cmd.join(" "), firstLine(err));
                }
                next(i + 1);
            });
        };
        next(0);
    }

    function firstLine(text) {
        return String(text ?? "").split("\n").map(l => l.trim()).find(l => l !== "")?.substring(0, 140) ?? "";
    }

    // A command and its whole output; done(code, stdout, stderr).
    function run(cmd, done) {
        const p = job.createObject(root, { command: ["sh", "-c", 'exec "$@"', "sh"].concat(cmd), done: done });
        p.running = true;
    }
    Component {
        id: job

        Process {
            id: proc
            property var done: null
            property int code: -1
            property int waiting: 3
            function step() {
                if (--waiting > 0)
                    return;
                const d = done;
                done = null;
                d?.(code, out.text, err.text);
                destroy();
            }
            stdout: StdioCollector { id: out; onStreamFinished: proc.step() }
            stderr: StdioCollector { id: err; onStreamFinished: proc.step() }
            onExited: c => { code = c; step(); }
        }
    }

    function saveState() {
        stateFile.setText(on ? JSON.stringify({ on: true, before: before }, null, 1) : "{}\n");
    }
    // After a restart: still on, and what to bring back.
    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text() || "{}");
                if (s.on === true && s.before && typeof s.before === "object") {
                    root.before = {
                        wifi: s.before.wifi === true,
                        wwan: s.before.wwan === true,
                        btUnblocked: s.before.btUnblocked === true,
                        btPowered: s.before.btPowered === true
                    };
                    root.on = true;
                    watching.restart();
                }
            } catch (e) {}
        }
    }
}
