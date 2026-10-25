pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Tailscale: whether it's on, this device, the others on your tailnet, the
// exit node; turn it on or off and pick an exit node.
//
// Reading needs nothing special (`tailscale status --json`, `tailscale
// debug prefs`). Changing anything needs root, or you as Tailscale's
// "operator": run once in a terminal  sudo tailscale set --operator=$USER
// Until then (canControl false) the shell only shows things and says how.
// It never tries a change to find out: it reads OperatorUser from the prefs.
//
// The commands it runs, each changing one setting and nothing else:
//   on          tailscale up     bare, with no flags: tailscale's special case that only
//                                sets WantRunning=true (cmd/tailscale/cli/up.go, simpleUp;
//                                only taken once logged in, not on NeedsLogin, so never here)
//   off         tailscale down   only sets WantRunning=false
//   exit node   tailscale set --exit-node=<its IPv4>   only ExitNodeIP/ExitNodeID
//   none        tailscale set --exit-node=
//
// Asks only while something shows it: every Style.tailscalePollOpen s
// while the control center is open, every Style.tailscalePollBar s while
// the bar item is on the bar; once at start (for the tile), nothing else.
//
// Tests: put a fake `tailscale` first on PATH (or MINE_TAILSCALE_CLI);
// MINE_TAILSCALE_DRYRUN=1 only prints the changes.
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_TAILSCALE_DRYRUN") === "1"
    readonly property string cli: Quickshell.env("MINE_TAILSCALE_CLI") || "tailscale"
    readonly property string user: Quickshell.env("USER") || ""
    readonly property string operatorCommand: "sudo tailscale set --operator=" + user

    property bool known: false          // the first answer came
    property bool installed: false
    // tailscaled's BackendState: Running, Stopped, NeedsLogin,
    // NeedsMachineAuth, Starting, NoState; "" = it didn't answer.
    property string state: ""
    property string readError: ""       // why it didn't answer
    property var self: null             // a device, below
    property var peers: []              // the others: online first, then by last seen
    property var health: []             // tailscaled's own warnings (lines)
    property string tailnet: ""
    property string operatorUser: ""
    property bool prefsKnown: false

    // A device: { id, name (unique on the tailnet), host, dns (full MagicDNS
    // name), ipv4, ipv6, os, online, lastSeen (Date or null), expired,
    // exitNode (traffic goes through it now), exitNodeOption }

    readonly property bool running: state === "Running"
    readonly property bool canControl: prefsKnown && user !== "" && operatorUser === user
    // On/off makes sense from these (NeedsLogin wants a browser: a terminal's job).
    readonly property bool switchable: state === "Running" || state === "Stopped"
    readonly property var exitNode: peers.find(p => p.exitNode) ?? null
    readonly property var exitOptions: peers.filter(p => p.exitNodeOption)
    readonly property int onlineCount: peers.filter(p => p.online).length

    // One line, for the tile, the bar item's tip and Settings.
    readonly property string summary: {
        if (busy !== "")
            return busy === "up" ? "Turning on…" : busy === "down" ? "Turning off…" : "Switching exit node…";
        if (!known)
            return "";
        if (!installed)
            return "Not installed";
        switch (state) {
        case "Running":
            return exitNode ? "Via " + exitNode.name
                : onlineCount === 0 ? "On · no other device online"
                : "On · " + onlineCount + (onlineCount === 1 ? " device" : " devices") + " online";
        case "Stopped": return "Off";
        case "NeedsLogin": return "Not logged in";
        case "NeedsMachineAuth": return "Waiting for approval";
        case "Starting": return "Starting…";
        case "": return "Service not running";
        }
        return state;
    }

    // Shorter, for the control center tile.
    readonly property string shortSummary: busy === "" && state === "Running"
        ? (exitNode ? "Via " + exitNode.name : onlineCount === 0 ? "On" : "On · " + onlineCount + " online")
        : summary

    // ---- Asking tailscaled ---------------------------------------------------------------
    // use("open", true) while the control center shows it, use("bar", true)
    // while the bar item is there; each turns the polling on and asks now.
    property int openUsers: 0
    property int barUsers: 0
    function use(kind, on) {
        if (kind === "open")
            openUsers = Math.max(0, openUsers + (on ? 1 : -1));
        else
            barUsers = Math.max(0, barUsers + (on ? 1 : -1));
        if (on)
            refresh();
    }
    function refresh() {
        if (!finder.running && !installed) {
            finder.running = true;
            return;
        }
        if (installed && !status.running)
            status.running = true;
    }
    // The prefs (who may change things, the exit node chosen): at start,
    // when the page opens and after each change.
    function readPrefs() {
        if (installed && !prefs.running)
            prefs.running = true;
    }

    Component.onCompleted: refresh()

    Timer {
        running: root.installed && (root.openUsers > 0 || root.barUsers > 0)
        interval: Math.max(2, root.openUsers > 0 ? Style.tailscalePollOpen : Style.tailscalePollBar) * 1000
        repeat: true
        onTriggered: root.refresh()
    }

    // Is there a tailscale at all? (Once; again only while it isn't.)
    Process {
        id: finder
        command: ["sh", "-c", 'command -v -- "$1" >/dev/null', "sh", root.cli]
        onExited: code => {
            root.installed = code === 0;
            if (root.installed) {
                status.running = true;
                prefs.running = true;
            } else {
                root.known = true;
            }
        }
    }

    // The answer is read when its output ends; tailscaled's complaint (it
    // isn't running…) from stderr, whichever of the two ends first.
    Process {
        id: status
        command: [root.cli, "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let s = null;
                try {
                    s = JSON.parse(text);
                } catch (e) {
                    s = null;
                }
                if (s === null || typeof s !== "object") {
                    // tailscaled isn't running (or the CLI went away).
                    root.state = "";
                    root.readError = root.firstLine(statusErr.text) || "tailscaled didn't answer";
                    root.self = null;
                    root.peers = [];
                    root.health = [];
                } else {
                    root.readError = "";
                    root.take(s);
                }
                root.known = true;
            }
        }
        stderr: StdioCollector {
            id: statusErr
            onStreamFinished: if (root.readError !== "" && root.firstLine(text) !== "") root.readError = root.firstLine(text)
        }
    }

    Process {
        id: prefs
        command: [root.cli, "debug", "prefs"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = null;
                try {
                    p = JSON.parse(text);
                } catch (e) {
                    p = null;
                }
                // OperatorUser is left out of the JSON while nobody is set.
                root.operatorUser = p && typeof p.OperatorUser === "string" ? p.OperatorUser : "";
                root.prefsKnown = p !== null;
            }
        }
    }

    // Names come from anyone on the tailnet: one line, no control or
    // direction-flipping characters.
    function clean(text) {
        return String(text ?? "").replace(/[\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g, " ")
            .replace(/\s+/g, " ").trim();
    }
    function firstLine(text) {
        const line = String(text ?? "").split("\n").map(l => l.trim()).find(l => l !== "") ?? "";
        return clean(line).substring(0, 160);
    }

    function device(n) {
        const ips = Array.isArray(n.TailscaleIPs) ? n.TailscaleIPs.map(String) : [];
        const seen = n.LastSeen ? new Date(n.LastSeen) : null;
        const dns = clean(n.DNSName).replace(/\.$/, "");
        const host = clean(n.HostName);
        const label = dns.split(".")[0];
        // Several machines can share a host name (old installs of the same
        // laptop: "laptop" four times); tailscale then gives each a MagicDNS
        // name with a number (laptop-1, laptop-2), and that's the one shown.
        const slug = host.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
        const numbered = slug !== "" && label !== slug && new RegExp("^" + slug + "-\\d+$").test(label);
        return {
            id: String(n.ID ?? n.PublicKey ?? dns),
            name: host === "" || numbered ? (label || host || ips[0] || "?") : host,
            host: host,
            dns: dns,
            label: label,
            ipv4: ips.find(ip => /^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) ?? "",
            ipv6: ips.find(ip => ip.includes(":")) ?? "",
            os: clean(n.OS).toLowerCase(),
            online: n.Online === true,
            // "0001-01-01T00:00:00Z" = never (or online now).
            lastSeen: seen && !isNaN(seen) && seen.getFullYear() > 2000 ? seen : null,
            expired: n.Expired === true,
            exitNode: n.ExitNode === true,
            exitNodeOption: n.ExitNodeOption === true
        };
    }

    function take(s) {
        state = typeof s.BackendState === "string" ? s.BackendState : "";
        tailnet = clean(s.CurrentTailnet?.Name ?? "");
        health = Array.isArray(s.Health) ? s.Health.map(h => clean(h)).filter(h => h !== "") : [];
        const me = s.Self ? device(s.Self) : null;
        const list = Object.values(s.Peer ?? {}).map(device);
        list.sort((a, b) => (b.online - a.online)
            || ((b.lastSeen?.getTime() ?? 0) - (a.lastSeen?.getTime() ?? 0))
            || a.name.localeCompare(b.name));
        self = me;
        peers = list;
    }

    // Offline and not seen for Style.tailscaleHideAfterDays (0 = never).
    function isOld(d) {
        if (d.online || Style.tailscaleHideAfterDays <= 0)
            return false;
        return d.lastSeen === null || Date.now() - d.lastSeen.getTime() > Style.tailscaleHideAfterDays * 86400000;
    }

    // "just now", "5 min ago", "3 h ago", "3 d ago", "4 mo ago".
    function ago(date) {
        if (!date)
            return "a long time ago";
        const s = Math.max(0, (Date.now() - date.getTime()) / 1000);
        if (s < 90)
            return "just now";
        if (s < 3600)
            return Math.round(s / 60) + " min ago";
        if (s < 86400)
            return Math.round(s / 3600) + " h ago";
        if (s < 86400 * 60)
            return Math.round(s / 86400) + " d ago";
        return Math.round(s / (86400 * 30)) + " mo ago";
    }

    // A Material Symbols glyph for tailscale's OS names.
    function glyphFor(d) {
        switch (d?.os ?? "") {
        case "android": return "smartphone";
        case "ios": return "phone_iphone";
        case "macos": return "laptop_mac";
        case "windows": return "desktop_windows";
        case "linux": return "computer";
        case "tvos": return "tv";
        case "freebsd": case "openbsd": return "dns";
        }
        return "devices";
    }

    // ---- Copying a device's address ------------------------------------------------------------
    // Style.tailscaleCopy picks what a click copies ("ip" or "name");
    // the other one is a right click (or a long press) away.
    property var copied: ({ id: "", text: "" })
    function addressOf(d, other) {
        const wantName = (Style.tailscaleCopy === "name") !== (other === true);
        return wantName ? (d.dns || d.ipv4) : (d.ipv4 || d.ipv6 || d.dns);
    }
    function copy(d, other) {
        const text = addressOf(d, other);
        if (text === "")
            return;
        if (dryRun)
            console.log("tailscale (dry run): wl-copy", JSON.stringify(text));
        else
            Quickshell.execDetached(["wl-copy", "--", text]);
        copied = { id: d.id, text: text };
        copiedTimer.restart();
    }
    function copyOperatorCommand() {
        if (dryRun)
            console.log("tailscale (dry run): wl-copy", JSON.stringify(operatorCommand));
        else
            Quickshell.execDetached(["wl-copy", "--", operatorCommand]);
        copied = { id: "operator", text: operatorCommand };
        copiedTimer.restart();
    }
    Timer {
        id: copiedTimer
        interval: 2500
        onTriggered: root.copied = { id: "", text: "" }
    }

    // ---- Changing things (only as the operator) ----------------------------------------------------
    property string busy: ""            // "up" | "down" | "exit" while one runs
    property string actionError: ""     // what the last one said when it failed

    function setRunning(on) {
        if (!canControl || busy !== "" || !switchable || on === running)
            return;
        act(on ? "up" : "down", on ? [cli, "up"] : [cli, "down"]);
    }
    function toggle() {
        setRunning(!running);
    }
    // A peer offering itself as an exit node, or null for none.
    function setExitNode(d) {
        if (!canControl || busy !== "" || !running)
            return;
        if (d === null) {
            if (exitNode !== null)
                act("exit", [cli, "set", "--exit-node="]);
            return;
        }
        // Only an address tailscale just listed as an exit node.
        const known = exitOptions.find(p => p.id === d.id);
        if (!known || !/^\d{1,3}(\.\d{1,3}){3}$/.test(known.ipv4) || known.exitNode)
            return;
        act("exit", [cli, "set", "--exit-node=" + known.ipv4]);
    }

    function act(what, cmd) {
        actionError = "";
        if (dryRun) {
            console.log("tailscale (dry run):", what, JSON.stringify(cmd));
            return;
        }
        busy = what;
        action.command = cmd;
        action.running = true;
        actionLimit.restart();
    }
    Process {
        id: action
        property int code: 0
        stderr: StdioCollector {
            id: actionErr
            // (Its end may come after the exit: the message wins over the code.)
            onStreamFinished: if (action.code !== 0 && root.firstLine(text) !== "") root.actionError = root.firstLine(text)
        }
        onStarted: code = 0
        onExited: exitCode => {
            code = exitCode;
            actionLimit.stop();
            if (exitCode !== 0)
                root.actionError = root.firstLine(actionErr.text) || ("tailscale exited with " + exitCode);
            root.busy = "";
            root.refresh();
            root.readPrefs();
        }
    }
    // `tailscale up` waits until it's running; it's on its way by then, so
    // stop waiting after a while and just look.
    Timer {
        id: actionLimit
        interval: 20000
        onTriggered: action.signal(15)
    }
}
