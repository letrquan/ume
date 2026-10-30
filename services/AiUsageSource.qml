import QtQuick
import Quickshell
import Quickshell.Io
import "aiusage.js" as Usage

// One of services/AiUsage.qml's two services (Claude or Codex): its sign-in
// file, its one usage address, and the answer read into plain numbers.
//
// The sign-in file is only read, never written, and its refresh token is
// never touched: refreshing would sign Claude Code or Codex out (the old
// refresh token stops working). The app refreshes the file itself when it
// runs; we read it again whenever it changes, and just before each check.
// An expired token (or an answer 401/403): "Sign-in expired", and no more
// checks until the file changes.
//
// The token lives only in memory here: it goes to curl as a header line on
// stdin (curl -H @-), never in a command line, an environment, a log, a
// file or an error text. Only to `url`, a fixed https address; no
// redirects followed.
Scope {
    id: root

    required property string service            // "claude" | "codex"
    required property string title              // "Claude", "Codex"
    required property string credPath
    required property string url
    required property string program            // curl
    property real warnAt: 80
    property real criticalAt: 95

    // AiUsage turns this on while someone shows the numbers (and not
    // locked or asleep).
    property bool wanted: false
    property real interval: 300000
    // Never two calls closer than this.
    property real minGap: 60000

    // "missing" (no sign-in file: hidden) | "idle" | "ok" | "expired" | "error"
    property string phase: "idle"
    readonly property bool present: credsThere
    property string error: ""
    property var data: null
    property string plan: ""
    property real fetchedAt: 0
    property real triedAt: 0
    property int backoffLevel: 0
    property real nextDelay: interval
    readonly property bool busy: proc.running
    // A new answer came in (AiUsage checks the thresholds and saves).
    signal updated()

    // ---- The sign-in file -------------------------------------------------------------------
    property bool credsThere: false
    property string token: ""
    property string accountId: ""
    property real expiresAt: 0
    // The token the service turned away (401/403): not tried again.
    property string refused: ""

    FileView {
        id: creds
        path: root.credPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.readCreds()
        onLoadFailed: root.credsGone()
    }

    function readCreds() {
        credsThere = true;
        let o = null;
        try {
            o = JSON.parse(creds.text());
        } catch (e) {
            o = null;
        }
        let t = "", id = "", exp = 0;
        if (service === "claude") {
            const c = o?.claudeAiOauth;
            t = c?.accessToken ?? "";
            exp = Number(c?.expiresAt) || 0;
            plan = Usage.claudePlan(c?.subscriptionType, c?.rateLimitTier);
        } else {
            t = o?.tokens?.access_token ?? "";
            id = o?.tokens?.account_id ?? "";
            exp = Usage.plainToken(t) ? Usage.jwtExpiry(t) : 0;
        }
        o = null;
        const usable = Usage.plainToken(t) && (service !== "codex" || Usage.plainId(id));
        const changed = usable && (t !== token || exp !== expiresAt);
        token = usable ? t : "";
        accountId = usable ? id : "";
        expiresAt = exp;
        if (!usable) {
            phase = "error";
            error = "Can't read the sign-in";
            return;
        }
        if (phase === "missing" || (phase === "expired" && token !== refused) || (phase === "error" && changed)) {
            phase = data ? "ok" : "idle";
            error = "";
        }
        if (expiredNow())
            markExpired(false);
        if (waitingForCreds) {
            waitingForCreds = false;
            go();
        } else if (changed && wanted && phase !== "expired") {
            schedule(1000);
        }
    }
    function credsGone() {
        credsThere = false;
        token = "";
        accountId = "";
        phase = "missing";
        error = "";
        waitingForCreds = false;
        timer.stop();
    }

    function expiredNow() {
        return expiresAt > 0 && expiresAt <= Date.now() + 30000;
    }
    function markExpired(byAnswer) {
        phase = "expired";
        error = "Sign-in expired — open " + (service === "claude" ? "Claude Code" : "Codex");
        if (byAnswer)
            refused = token;
        timer.stop();
        console.log("aiusage:", service, byAnswer ? "the service says the sign-in expired" : "the sign-in has expired", "- waiting for the app to renew it");
    }

    // ---- Checking ------------------------------------------------------------------------------
    // Check now (if allowed: not more often than minGap, not while expired).
    function check(why) {
        if (!wanted || proc.running || phase === "missing")
            return;
        if (Date.now() - triedAt < minGap) {
            schedule(minGap - (Date.now() - triedAt));
            return;
        }
        // The newest token first (Claude Code may have renewed it).
        waitingForCreds = true;
        creds.reload();
    }
    property bool waitingForCreds: false

    function go() {
        if (!wanted || proc.running || !credsThere)
            return;
        if (token === "") {
            phase = "error";
            error = "Can't read the sign-in";
            return;
        }
        if (expiredNow()) {
            markExpired(false);
            return;
        }
        if (phase === "expired" && token === refused)
            return;
        triedAt = Date.now();
        // Header lines, read by curl from stdin (-H @-).
        const head = service === "claude"
            ? "Authorization: Bearer " + token + "\nanthropic-beta: oauth-2025-04-20\n"
            : "Authorization: Bearer " + token + "\nChatGPT-Account-Id: " + accountId + "\nUser-Agent: codex_cli_rs\n";
        proc.input = head;
        proc.command = [program, "-sS", "--proto", "=https", "--max-time", "15", "--max-filesize", "1000000",
                        "-H", "@-", "-w", "\\n%{http_code}", "--", url];
        proc.stdinEnabled = true;
        proc.running = true;
    }

    // The next check in `ms` (the timer only runs while wanted).
    function schedule(ms) {
        timer.stop();
        if (!wanted || phase === "missing" || phase === "expired")
            return;
        timer.interval = Math.max(1000, ms);
        timer.start();
    }
    Timer {
        id: timer
        onTriggered: root.check("timer")
    }
    onWantedChanged: {
        if (!wanted) {
            timer.stop();
            return;
        }
        // Back (unlocked, the bar item shown): at once if it's been a while.
        const since = Date.now() - fetchedAt;
        schedule(since >= nextDelay ? 0 : nextDelay - since);
    }

    function answered(code, httpCode, body) {
        if (code !== 0) {
            // curl's own failure (no network, timed out): its words aren't shown.
            error = code === 28 ? "Timed out" : code === 6 || code === 7 ? "No connection" : "Couldn't check (curl " + code + ")";
            backOff();
            return;
        }
        if (httpCode === 401 || httpCode === 403) {
            markExpired(true);
            return;
        }
        if (httpCode === 429 || httpCode >= 500) {
            error = httpCode === 429 ? "Too many checks, waiting" : "The service had a problem (" + httpCode + ")";
            backOff();
            return;
        }
        if (httpCode !== 200) {
            error = "Unexpected answer (" + httpCode + ")";
            phase = data ? "ok" : "error";
            backoffLevel = 0;
            nextDelay = interval;
            schedule(nextDelay);
            return;
        }
        let o = null;
        try {
            o = JSON.parse(body);
        } catch (e) {
            o = null;
        }
        const got = service === "claude" ? Usage.parseClaude(o, warnAt, criticalAt) : Usage.parseCodex(o, warnAt, criticalAt);
        o = null;
        if (!got) {
            console.warn("aiusage:", service, "answer not understood (" + body.length + " bytes)");
            error = "Answer not understood";
            phase = data ? "ok" : "error";
        } else {
            if (service === "codex" && got.plan !== "")
                plan = got.plan;
            data = got;
            fetchedAt = Date.now();
            error = "";
            phase = "ok";
            updated();
        }
        backoffLevel = 0;
        nextDelay = interval;
        schedule(nextDelay);
    }

    // 429, 5xx, no network: twice as long each time, up to 30 min.
    function backOff() {
        backoffLevel = Math.min(backoffLevel + 1, 10);
        nextDelay = Math.min(1800000, interval * Math.pow(2, backoffLevel));
        phase = data ? "ok" : "error";
        console.log("aiusage:", service, error, "- next check in", Math.round(nextDelay / 60000), "min");
        schedule(nextDelay);
    }

    // Cached numbers from the last run (AiUsage reads its file at start).
    function restore(saved) {
        if (!saved || typeof saved !== "object" || data)
            return;
        data = saved.data ?? null;
        fetchedAt = Number(saved.at) || 0;
        if (typeof saved.plan === "string" && plan === "")
            plan = saved.plan;
        if (data && phase === "idle")
            phase = "ok";
    }

    // The answer once curl has exited AND its output is read (either order).
    Process {
        id: proc
        property string input: ""
        property int code: -1
        property int pending: 0
        onRunningChanged: if (running) {
            code = -1;
            pending = 3;
        }
        onStarted: {
            write(input);
            input = "";
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            id: out
            onStreamFinished: proc.settle()
        }
        // curl's own error words are never shown or logged.
        stderr: StdioCollector {
            onStreamFinished: proc.settle()
        }
        onExited: exitCode => {
            code = exitCode;
            settle();
        }
        function settle() {
            if (pending <= 0 || --pending > 0)
                return;
            const text = out.text;
            const cut = text.lastIndexOf("\n");
            const httpCode = cut >= 0 ? parseInt(text.substring(cut + 1), 10) : NaN;
            root.answered(code === 0 && !isFinite(httpCode) ? -1 : code, httpCode, cut >= 0 ? text.substring(0, cut) : "");
        }
    }
}
