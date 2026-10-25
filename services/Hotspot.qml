pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "netqr.js" as NetQr

// The Wi-Fi hotspot (the control center's "hotspot" tile and page).
// NetworkManager does the work:
//   on   the first time  nmcli device wifi hotspot ifname <card> con-name Hotspot [ssid <Style.hotspotName>]
//        (NetworkManager makes up the password and keeps it in that profile:
//        the shell never passes, saves or logs one); later ones just
//        nmcli connection up id Hotspot (and connection modify … ssid when
//        Style.hotspotName changed)
//   off  nmcli connection down id Hotspot, then connection up uuid <the
//        Wi-Fi network you were on>, saved in ~/.local/state/mine-shell/
//        hotspot.json in case the shell restarts meanwhile
// The Wi-Fi card can't be on a network and be a hotspot at once
// (NetworkManager uses the one card for one or the other), so turning it on
// leaves the network you're on: the first click only says so (tap() arms,
// a second click within 4 s goes). Devices on the hotspot get this
// laptop's internet only through another link (a cable, USB tethering).
//
// What's on: one `nmcli -t device` read when the tile or page shows, and
// again whenever NetworkManager's Wi-Fi card changes mode. The page reads
// the name and password (nmcli -s) while it's open (reveal()) and forgets
// them when it closes (conceal()).
//
// Tests: MINE_NMCLI (the nmcli to run), MINE_HOTSPOT_DRYRUN=1 (changes are
// printed, not run; reads still run), MINE_HOTSPOT_STATE (where the network
// to go back to is kept).
Singleton {
    id: root

    readonly property string nmcli: Quickshell.env("MINE_NMCLI") || "nmcli"
    readonly property bool dryRun: Quickshell.env("MINE_HOTSPOT_DRYRUN") === "1"
    readonly property string statePath: Quickshell.env("MINE_HOTSPOT_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/hotspot.json")
    readonly property string conName: "Hotspot"

    property bool known: false
    property string device: ""          // the Wi-Fi card (wlan0); "" = none
    property string current: ""         // the profile on it now; "" = none
    readonly property bool on: device !== "" && current === conName
    // Leaving a Wi-Fi network for the hotspot (the warning's network).
    readonly property string leaving: on || current === "" ? "" : current
    property string busy: ""            // "on" | "off" while switching ("forget": the profile)
    property string error: ""
    property bool armed: false          // first click done, a second turns it on

    property string ssid: ""            // its network name, while on
    // Only while revealed (the page is open) and on.
    property string password: ""
    property string secretError: ""
    property bool revealed: false
    readonly property string qrText: on && ssid !== "" && password !== "" ? NetQr.wifiText(ssid, "WPA", password, false) : ""

    // The Wi-Fi network to go back to.
    property string previous: ""        // its uuid
    property string previousName: ""

    // One line, for the tile.
    readonly property string detail: busy === "on" ? "Turning on…"
        : busy === "off" ? "Turning off…"
        : error !== "" ? error
        : armed ? "Leaves " + leaving + " · click again"
        : on ? (ssid !== "" ? ssid : "On")
        : !known ? ""
        : device === "" ? "No Wi-Fi card"
        : "Off"

    // ---- Who's looking -------------------------------------------------------------------
    property int users: 0
    function use(yes) {
        users = Math.max(0, users + (yes ? 1 : -1));
        if (yes)
            refresh();
    }

    // NetworkManager switched the card (here or elsewhere): look again.
    Connections {
        target: ControlState.wifiDevice
        ignoreUnknownSignals: true
        function onModeChanged() { if (root.users > 0) settle.restart(); }
        function onConnectedChanged() { if (root.users > 0) settle.restart(); }
    }
    Timer {
        id: settle
        interval: 600
        onTriggered: root.refresh()
    }

    function refresh() {
        if (reading)
            return;
        reading = true;
        run([nmcli, "-t", "-e", "no", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"], (code, out) => {
            reading = false;
            const wifi = NetQr.rows(out, 4).find(r => r[1] === "wifi");
            device = wifi ? wifi[0] : "";
            current = wifi && wifi[2].startsWith("connected") ? wifi[3] : "";
            known = true;
            if (on)
                readName();
            else {
                ssid = "";
                password = "";
            }
        });
    }
    property bool reading: false

    // ---- On and off ----------------------------------------------------------------------
    // The tile's click and the page's switch.
    function tap() {
        if (busy !== "")
            return;
        if (on) {
            setOn(false);
            return;
        }
        if (leaving !== "" && !armed) {
            armed = true;
            disarm.restart();
            return;
        }
        setOn(true);
    }
    Timer {
        id: disarm
        interval: 4000
        onTriggered: root.armed = false
    }

    function setOn(want) {
        if (busy !== "" || want === on)
            return;
        armed = false;
        error = "";
        if (device === "") {
            error = known ? "No Wi-Fi card" : "";
            refresh();
            return;
        }
        busy = want ? "on" : "off";
        if (want)
            turnOn();
        else
            turnOff();
    }

    function turnOn() {
        // Which Wi-Fi network we leave (to come back to it).
        run([nmcli, "-t", "-e", "no", "-f", "UUID,TYPE,DEVICE,NAME", "connection", "show", "--active"], (code, out) => {
            const was = NetQr.rows(out, 4).find(r => r[1] === "802-11-wireless" && r[2] === device && r[3] !== conName);
            previous = was ? was[0] : "";
            previousName = was ? was[3] : "";
            saveState();
            // Is there a hotspot profile already (and with which name)?
            run([nmcli, "-t", "-e", "no", "-f", "802-11-wireless.ssid", "connection", "show", "id", conName], (code2, out2) => {
                const exists = code2 === 0;
                const have = NetQr.fields(out2)["802-11-wireless.ssid"] ?? "";
                const want = Style.hotspotName;
                const steps = [];
                if (exists && want !== "" && have !== want)
                    steps.push(["connection", "modify", "id", conName, "802-11-wireless.ssid", want]);
                if (exists)
                    steps.push(["-w", "30", "connection", "up", "id", conName, "ifname", device]);
                else
                    steps.push(["-w", "30", "device", "wifi", "hotspot", "ifname", device, "con-name", conName].concat(want !== "" ? ["ssid", want] : []));
                change(steps, ok => {
                    busy = "";
                    if (!ok && previous !== "") {
                        const back = previous;
                        previous = "";
                        previousName = "";
                        saveState();
                        const why = error;
                        change([["-w", "20", "connection", "up", "uuid", back]], () => {
                            error = why;
                            refresh();
                        });
                    } else {
                        refresh();
                    }
                });
            });
        });
    }

    function turnOff() {
        const steps = [["-w", "15", "connection", "down", "id", conName]];
        if (previous !== "")
            steps.push(["-w", "30", "connection", "up", "uuid", previous]);
        change(steps, ok => {
            busy = "";
            ssid = "";
            password = "";
            // Back on it (or it's gone): nothing to come back to any more.
            if (ok || previous === "") {
                previous = "";
                previousName = "";
                saveState();
            }
            refresh();
        });
    }

    // Changes, one after the other; the first that fails stops the rest
    // and says why (its first line).
    function change(steps, done) {
        if (steps.length === 0) {
            done(true);
            return;
        }
        const args = steps[0];
        const rest = steps.slice(1);
        if (dryRun) {
            console.log("hotspot (dry run): nmcli " + args.join(" "));
            Qt.callLater(() => change(rest, done));
            return;
        }
        console.log("hotspot: nmcli " + args.join(" "));
        run([nmcli].concat(args), (code, out, err) => {
            if (code !== 0) {
                error = firstLine(err) || firstLine(out) || "nmcli failed (" + code + ")";
                console.log("hotspot: failed:", error);
                done(false);
            } else {
                change(rest, done);
            }
        });
    }

    // Settings → Control center → New password: the profile goes, the next
    // hotspot makes a new one (and NetworkManager a new password).
    function forgetProfile() {
        if (busy !== "" || on)
            return;
        error = "";
        busy = "forget";
        change([["connection", "delete", "id", conName]], ok => {
            busy = "";
            // There was none: nothing to forget, that's fine.
            if (!ok && /no such connection|unknown connection/i.test(error))
                error = "";
            refresh();
        });
    }

    // ---- The name and password, for the page -----------------------------------
    function reveal() {
        revealed = true;
        if (on)
            readName();
    }
    function conceal() {
        revealed = false;
        password = "";
        secretError = "";
    }
    // The name (no secret: read whenever it's on); the password only while
    // revealed (-s: NetworkManager hands it out; it may ask for yours first).
    function readName() {
        const fields = revealed ? "802-11-wireless.ssid,802-11-wireless-security.psk" : "802-11-wireless.ssid";
        const args = ["-t", "-e", "no"].concat(revealed ? ["-s"] : []).concat(["-f", fields, "connection", "show", "id", conName]);
        run([nmcli].concat(args), (code, out) => {
            const f = NetQr.fields(out);
            if (!on)
                return;
            ssid = f["802-11-wireless.ssid"] ?? ssid;
            if (!revealed)
                return;
            password = f["802-11-wireless-security.psk"] ?? "";
            secretError = code !== 0 || password === "" ? "Couldn't read the password" : "";
        });
    }

    // ---- Small things ------------------------------------------------------------------
    function firstLine(text) {
        return String(text ?? "").split("\n").map(l => l.trim()).find(l => l !== "")?.substring(0, 140) ?? "";
    }

    // A command and its whole output; done(code, stdout, stderr). Run through
    // sh so a missing command is an exit code (127), not a silent failure.
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
        stateFile.setText(previous === "" ? "{}\n" : JSON.stringify({ previous: previous, previousName: previousName }, null, 1));
    }
    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text() || "{}");
                if (typeof s.previous === "string" && /^[0-9a-fA-F-]{8,64}$/.test(s.previous)) {
                    root.previous = s.previous;
                    root.previousName = typeof s.previousName === "string" ? s.previousName : "";
                }
            } catch (e) {}
        }
    }
}
