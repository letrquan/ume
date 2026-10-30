pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "aiusage.js" as Usage

// How much of your Claude and Codex limits is used, for the "AI usage" bar
// item (two small rings: Claude's 5-hour and weekly, Codex's window) and its
// popup (bar/AiUsageItem.qml, control/AiUsagePopup.qml).
//
// Each service (services/AiUsageSource.qml) reads its app's own sign-in
// file (~/.claude/.credentials.json, ~/.codex/auth.json) and asks its one
// usage address with curl:
//   Claude  https://api.anthropic.com/api/oauth/usage
//   Codex   https://chatgpt.com/backend-api/wham/usage
// A service whose sign-in file isn't there is hidden. Tokens are never
// refreshed, written, logged or shown (see AiUsageSource).
//
// Checked only while the bar item or the popup is there (use()), every
// Style.aiUsagePoll minutes (never closer than a minute; twice as long after
// each "too many" or server error, up to 30 min), and not while locked or
// asleep. Opening the popup checks at once when the numbers are over a
// minute old.
//
// A notification once per window when it passes Style.aiUsageWarnAt and
// Style.aiUsageCriticalAt percent (Style.aiUsageNotify). The numbers, the
// reset times and which notifications were sent are kept in
// ~/.local/state/mine-shell/aiusage.json (no ids, no email, no token), so the
// popup has something at once after a restart.
//
// Tests: MINE_AIUSAGE_CURL (the program run instead of curl, same
// arguments, headers on stdin), MINE_AIUSAGE_CLAUDE / MINE_AIUSAGE_CODEX
// (the sign-in files), MINE_AIUSAGE_STATE (the cache), MINE_AIUSAGE_GAP
// (seconds instead of the one-minute floor), MINE_AIUSAGE_DRYRUN=1
// (notifications only printed).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property bool dryRun: Quickshell.env("MINE_AIUSAGE_DRYRUN") === "1"
    readonly property string program: Quickshell.env("MINE_AIUSAGE_CURL") || "curl"
    readonly property string statePath: Quickshell.env("MINE_AIUSAGE_STATE") || (home + "/.local/state/mine-shell/aiusage.json")
    readonly property real minGap: (Number(Quickshell.env("MINE_AIUSAGE_GAP")) || 60) * 1000

    // Bar items and popups showing the numbers right now.
    property int users: 0
    function use(on) {
        users = Math.max(0, users + (on ? 1 : -1));
    }

    // Not while locked (lock.qml's marker) or asleep (Locker).
    readonly property string marker: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-lock.secure"
    property bool markerThere: false
    readonly property bool locked: markerFile.path !== "" && markerThere
    FileView {
        id: markerFile
        path: root.users > 0 ? root.marker : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.markerThere = true
        onLoadFailed: root.markerThere = false
    }
    readonly property bool wanted: users > 0 && !locked && !Locker.sleeping

    readonly property real interval: Math.max(1, Style.aiUsagePoll) * 60000

    AiUsageSource {
        id: claudeSource
        service: "claude"
        title: "Claude"
        credPath: Quickshell.env("MINE_AIUSAGE_CLAUDE") || (root.home + "/.claude/.credentials.json")
        url: "https://api.anthropic.com/api/oauth/usage"
        program: root.program
        wanted: root.wanted
        interval: root.interval
        minGap: root.minGap
        warnAt: Style.aiUsageWarnAt
        criticalAt: Style.aiUsageCriticalAt
        onUpdated: root.updated(claudeSource)
    }
    AiUsageSource {
        id: codexSource
        service: "codex"
        title: "Codex"
        credPath: Quickshell.env("MINE_AIUSAGE_CODEX") || (root.home + "/.codex/auth.json")
        url: "https://chatgpt.com/backend-api/wham/usage"
        program: root.program
        wanted: root.wanted
        interval: root.interval
        minGap: root.minGap
        warnAt: Style.aiUsageWarnAt
        criticalAt: Style.aiUsageCriticalAt
        onUpdated: root.updated(codexSource)
    }
    readonly property AiUsageSource claude: claudeSource
    readonly property AiUsageSource codex: codexSource
    readonly property bool any: claude.present || codex.present

    // Check both now (the popup's Refresh, IPC), within the one-minute floor.
    function refresh() {
        claude.check("refresh");
        codex.check("refresh");
    }
    // The popup opened: fresh numbers if the ones shown are over a minute old.
    function refreshIfOld() {
        const now = Date.now();
        for (const s of [claude, codex])
            if (now - s.fetchedAt > 60000)
                s.check("popup");
    }

    // The windows of a service, for the rings and rows: [{ label, percent,
    // resetsAt, severity }] (Claude: 5-hour, weekly, then each model's).
    function windowsOf(s) {
        const d = s?.data;
        if (!d)
            return [];
        if (s.service === "claude")
            return [d.session, d.weekly].filter(w => w).concat(d.models ?? []);
        return d.windows ?? [];
    }
    function colorOf(severity) {
        return severity === "critical" ? Colors.error : severity === "warn" ? Style.aiUsageWarnColor : Colors.primary;
    }
    function resetText(at) {
        return Usage.resetText(at, Date.now(), Style.clock24h);
    }
    function agoText(at) {
        return Usage.agoText(at, Date.now());
    }

    // ---- Notifications at warnAt / criticalAt, once per window ------------------------------------
    // "<service>|<window>|<threshold>" -> that window's reset time. Another
    // reset time (an hour or more off) is the next window: it may say so again.
    property var notified: ({})

    function updated(s) {
        const now = Date.now();
        for (const key of Object.keys(notified))
            if (!(notified[key] > now - 3600000))
                delete notified[key];
        if (Style.aiUsageNotify) {
            for (const w of windowsOf(s)) {
                const steps = [Style.aiUsageCriticalAt, Style.aiUsageWarnAt].filter(t => w.percent >= t);
                if (steps.length === 0)
                    continue;
                // No reset time given: the same window for the next 5 hours.
                const at = w.resetsAt > 0 ? w.resetsAt : now + 5 * 3600000;
                const keyOf = t => s.service + "|" + w.label + "|" + t;
                const seen = t => notified[keyOf(t)] !== undefined && Math.abs(notified[keyOf(t)] - at) < 3600000;
                // Passing both at once says the higher one only.
                if (!seen(steps[0]))
                    notify(s, w, steps[0]);
                for (const t of steps)
                    notified[keyOf(t)] = at;
            }
        }
        save();
    }

    function notify(s, w, threshold) {
        const summary = s.title + ": " + Math.round(w.percent) + "% of the " + (w.label === "Weekly" ? "weekly" : w.label) + " limit used";
        const body = (w.resetsAt > 0 ? resetText(w.resetsAt).replace(/^resets/, "It resets") : "") || "";
        const cmd = ["notify-send", "-a", "AI usage", "-i", threshold >= Style.aiUsageCriticalAt ? "dialog-warning" : "dialog-information",
                     "-u", threshold >= Style.aiUsageCriticalAt ? "critical" : "normal", "--", summary, body];
        console.log("aiusage: notification:", summary);
        if (dryRun)
            console.log("aiusage (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // ---- The cache ------------------------------------------------------------------------------
    property bool loadedOnce: false
    StateFile {
        id: file
        path: root.statePath
        onLoaded: text => {
            let saved = {};
            try {
                saved = text === "" ? {} : JSON.parse(text);
            } catch (e) {
                saved = {};
            }
            if (saved && typeof saved === "object") {
                claudeSource.restore(saved.claude);
                codexSource.restore(saved.codex);
                if (saved.notified && typeof saved.notified === "object")
                    root.notified = Object.assign({}, saved.notified, root.notified);
            }
            root.loadedOnce = true;
        }
        onRefused: why => {
            console.warn("aiusage:", root.statePath, "is", why + ", not read; the next save puts a real file there");
            root.loadedOnce = true;
        }
    }
    Component.onCompleted: file.load()

    function cacheOf(s) {
        return s.data ? { at: s.fetchedAt, plan: s.plan, data: s.data } : null;
    }
    function save() {
        if (!loadedOnce)
            return;
        file.save(JSON.stringify({ version: 1, claude: cacheOf(claude), codex: cacheOf(codex), notified: notified }, null, 1) + "\n");
    }

    // qs -c mine ipc call aiusage status: the numbers only.
    function status() {
        const one = s => ({
            shown: s.present, state: s.phase, error: s.error, plan: s.plan,
            updated: s.fetchedAt > 0 ? new Date(s.fetchedAt).toISOString() : "",
            windows: windowsOf(s).map(w => ({ label: w.label, percent: w.percent, severity: w.severity,
                                              resets: w.resetsAt > 0 ? new Date(w.resetsAt).toISOString() : "" })),
            breakdown: s.service === "claude" ? (s.data?.breakdown ?? []) : undefined
        });
        return JSON.stringify({ checking: wanted, claude: one(claude), codex: one(codex) });
    }
}
