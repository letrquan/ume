pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Your phone, through KDE Connect (`sudo pacman -S kdeconnect`, the app on
// the phone, ports 1714–1764 open in ufw; mango starts kdeconnectd, see
// ~/.config/mango/shell-mine.conf).
//
// What it knows: the phone's name, whether it's connected, its battery
// (scripts/phone-status.sh asks kdeconnectd over D-Bus, read-only; every
// Style.phoneRefresh seconds while something shows it, once at start).
// What it does: ring, ping, send the clipboard or files through
// kdeconnect-cli; pair through scripts/phone-pair.sh (each step only if the
// device is still as shown, and accepting only with the key you compared).
// kdeconnectd itself puts the phone's notifications up (as the shell's own
// popups, with Reply) and keeps the clipboard in sync.
//
// devices: [{ id, name, type ("phone", "tablet"…), reachable, paired,
//             pairRequested (we asked), pairRequestedByPeer (it asked),
//             key (the pairing key while one side asks, else ""),
//             charge (-1 = unknown), charging }]
//
// Tests: MINE_PHONE_STATUS = a command printing that JSON instead,
// MINE_PHONE_CLI = instead of kdeconnect-cli (and the file picker's
// kdialog and the pairing script's busctl are found through PATH),
// MINE_PHONE_DRYRUN=1 only prints.
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_PHONE_DRYRUN") === "1"
    readonly property string statusCommand: Quickshell.env("MINE_PHONE_STATUS")
        || (Quickshell.shellDir + "/scripts/phone-status.sh")
    readonly property string cli: Quickshell.env("MINE_PHONE_CLI") || "kdeconnect-cli"
    readonly property string pairScript: Quickshell.shellDir + "/scripts/phone-pair.sh"

    property bool known: false          // the first answer came
    property bool installed: false
    property bool running: false
    property var devices: []

    // The phone shown: the one named (or with the id) in Style.phoneDevice,
    // else the first paired one, connected ones first.
    readonly property var device: {
        const want = Style.phoneDevice.trim();
        if (want !== "") {
            const named = devices.find(d => d.paired && (d.name === want || d.id === want));
            if (named)
                return named;
        }
        const paired = devices.filter(d => d.paired);
        return paired.find(d => d.reachable) ?? paired[0] ?? null;
    }
    readonly property bool connected: device !== null && device.reachable
    readonly property int charge: connected ? device.charge : -1
    readonly property bool charging: connected && device.charging
    readonly property bool low: charge >= 0 && charge < Style.phoneBatteryWarn && !charging
    // Everything else worth showing: ones asking to pair first (a request
    // lasts 30 s), then other paired ones (so a pairing you didn't expect
    // shows up too) and ones just there on the network.
    readonly property var others: {
        const rest = devices.filter(d => d.id !== device?.id && (d.paired || d.reachable || d.pairRequested));
        return devices.filter(d => d.pairRequestedByPeer).concat(rest.filter(d => !d.pairRequestedByPeer));
    }
    // A pairing going on, either way.
    readonly property bool pairing: devices.some(d => d.pairRequested || d.pairRequestedByPeer)

    // A Material Symbols glyph for a KDE Connect device type.
    function glyphFor(d) {
        switch (d?.type ?? "") {
        case "tablet": return "tablet_android";
        case "tv": return "tv";
        case "desktop": return "desktop_windows";
        case "laptop": return "laptop";
        }
        return "smartphone";
    }

    // One line: for the control center tile and Settings.
    readonly property string summary: {
        if (!known)
            return "";
        if (!installed)
            return "Not installed";
        if (!running)
            return "KDE Connect isn't running";
        if (device === null)
            return others.some(d => d.pairRequestedByPeer) ? "Wants to pair" : "No phone paired";
        if (!connected)
            return "Not connected";
        return charge >= 0 ? charge + "%" + (charging ? " · charging" : "") : "Connected";
    }

    // ---- Asking kdeconnectd -----------------------------------------------------------
    // Polls only while something shows it (the bar item, the control
    // center); anything else asks once with refresh().
    property int users: 0
    function use(on) {
        users = Math.max(0, users + (on ? 1 : -1));
        if (on)
            refresh();
    }
    function refresh() {
        if (!status.running)
            status.running = true;
    }
    // After pairing or sending: the daemon needs a moment to change state.
    function refreshSoon() {
        soon.restart();
    }

    Component.onCompleted: refresh()

    Timer {
        running: root.users > 0
        interval: Math.max(5, Style.phoneRefresh) * 1000
        repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        id: soon
        interval: 1500
        onTriggered: root.refresh()
    }

    Process {
        id: status
        command: [root.statusCommand]
        stdout: StdioCollector {
            onStreamFinished: {
                let s;
                try {
                    s = JSON.parse(text);
                } catch (e) {
                    return;     // half a line (it was stopped): keep what we had
                }
                root.installed = s.installed === true;
                root.running = s.running === true;
                const list = Array.isArray(s.devices) ? s.devices : [];
                // Names come from anyone on the network (kdeconnectd already
                // drops <>"' and such): one line, no control or
                // direction-flipping characters.
                for (const d of list)
                    d.name = String(d.name ?? "").replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, " ")
                        .replace(/\s+/g, " ").trim();
                root.noteEnded(root.devices, list);
                root.devices = list;
                root.known = true;
            }
        }
    }

    // ---- Doing things ---------------------------------------------------------------------
    // What was just done ("ring", "ping", "clipboard", "files"), for a short
    // "Sent" in the page; it clears itself.
    property string done: ""
    Timer {
        id: doneTimer
        interval: 2500
        onTriggered: root.done = ""
    }

    function run(what, args) {
        const cmd = [root.cli].concat(args);
        if (dryRun)
            console.log("phone (dry run):", what, JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
        done = what;
        doneTimer.restart();
    }

    // Rings even when the phone is on silent (to find it).
    function ring() {
        if (connected)
            run("ring", ["-d", device.id, "--ring"]);
    }
    function ping() {
        if (connected)
            run("ping", ["-d", device.id, "--ping"]);
    }
    function sendClipboard() {
        if (connected)
            run("clipboard", ["-d", device.id, "--send-clipboard"]);
    }
    function share(paths) {
        if (connected && paths.length > 0)
            run("files", ["-d", device.id, "--share"].concat(paths));
    }
    // ---- Pairing ------------------------------------------------------------------------------
    // The page asks twice before any of these (see PhonePage). Each one runs
    // scripts/phone-pair.sh, which checks again right before, on the daemon
    // itself, that the device is still as shown (and still has that key).
    function pair(d) {                  // ask it to pair; then the key shows
        if (d && !d.paired && !d.pairRequested && !d.pairRequestedByPeer)
            pairStep("request", d, "");
    }
    function cancelPairing(d) {         // take our own request back
        if (d?.pairRequested)
            pairStep("cancel", d, "");
    }
    // Say yes to its request: only with the key it shows right now, which
    // you compared with the one on your phone.
    function acceptPairing(d, key) {
        if (d?.pairRequestedByPeer && /^[0-9A-F]{8}$/.test(key) && key === d.key)
            pairStep("accept", d, key);
    }
    function rejectPairing(d) {
        if (d?.pairRequestedByPeer)
            pairStep("reject", d, "");
    }

    function pairStep(what, d, key) {
        if (!/^[A-Za-z0-9_]+$/.test(d.id) || pairer.running)
            return;
        const cmd = [root.pairScript, what, d.id].concat(key !== "" ? [key] : []);
        if (dryRun) {
            console.log("phone (dry run):", what, JSON.stringify(cmd));
            return;
        }
        pairer.what = what;
        pairer.deviceId = d.id;
        pairer.command = cmd;
        pairer.running = true;
    }
    Process {
        id: pairer
        property string what: ""
        property string deviceId: ""
        onExited: code => {
            const text = code === 3 ? "It changed meanwhile: look again"
                : code !== 0 ? "KDE Connect didn't answer"
                : what === "accept" ? "Paired"
                : what === "reject" ? "Said no"
                : what === "cancel" ? "Cancelled" : "";
            if (text !== "")
                root.note(deviceId, text);
            root.refresh();
            root.refreshSoon();
        }
    }

    // What just happened to a pairing, under that device's name: { id, text };
    // it clears itself.
    property var pairNote: ({ id: "", text: "" })
    function note(id, text) {
        pairNote = { id: id, text: text };
        noteTimer.restart();
    }
    Timer {
        id: noteTimer
        interval: 6000
        onTriggered: root.pairNote = { id: "", text: "" }
    }
    // A pairing that ended on its own (or from the phone): say so, unless
    // we just did it ourselves.
    function noteEnded(before, after) {
        for (const old of before) {
            const now = after.find(d => d.id === old.id);
            if (!old.paired && now?.paired && pairNote.id !== old.id)
                note(old.id, "Paired");
            else if ((old.pairRequested || old.pairRequestedByPeer) && now && !now.paired
                     && !now.pairRequested && !now.pairRequestedByPeer && pairNote.id !== old.id)
                note(old.id, old.pairRequested ? "Not paired: it said no, or didn't answer in 30 s"
                    : "The request ended (cancelled, or 30 s passed)");
        }
    }

    // Pick files (KDE's file dialog, or GNOME's zenity), then send them.
    property string pickerError: ""
    function sendFiles() {
        if (!connected || picker.running)
            return;
        pickerError = "";
        picker.running = true;
    }
    Process {
        id: picker
        command: ["sh", "-c",
            'if command -v kdialog >/dev/null; then exec kdialog --title "Send to $1" --getopenfilename "$HOME" --multiple --separate-output; '
            + 'elif command -v zenity >/dev/null; then exec zenity --file-selection --multiple --separator="\n" --title="Send to $1"; '
            + 'else exit 127; fi', "sh", root.device?.name ?? "phone"]
        stdout: StdioCollector {
            onStreamFinished: {
                const paths = text.split("\n").map(p => p.trim()).filter(p => p !== "");
                root.share(paths);
            }
        }
        onExited: code => {
            if (code === 127)
                root.pickerError = "To pick files: sudo pacman -S kdialog (or zenity)";
        }
    }
}
