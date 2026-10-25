pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "translate.js" as Lang

// Translating text with Google Translate, over HTTPS (curl). The text
// goes to clients5.google.com (the endpoint Chrome's translate extension
// uses; translate.googleapis.com answers "429 Sorry" over HTTPS from here)
// on curl's stdin, so it is never in a
// command line (`ps`) or a log, and only an https address is followed;
// nothing else is sent. (Not translate-shell: its engines talk plain HTTP,
// so anyone on the same Wi-Fi could read and change the text.)
//
// Which way (Style.translatePair, "vi:en": your language, then the other
// one): text that looks like yours goes to the other language, anything
// else to yours. "Looks like" (translate.js): Vietnamese by its letters
// (đ ơ ư ạ ả …), Japanese, Korean, Chinese, Russian, Thai, Arabic, Hebrew,
// Greek and Hindi by their script; other languages in Latin letters can't
// be told apart, so with such a first language everything goes to it.
//
// API (Translator.…; the screenshot's translate card uses it, a launcher
// prefix can too):
//   request(id, text, target) → bool
//       id: any string; the answer comes back with it. text: what to
//       translate (cut at maxLength). target: a language code ("en", "vi",
//       "ja", …), or "auto" / "" for the pair's rule above. false (and no
//       answer) for empty text.
//   signal finished(id, ok, translation, from, to, error)
//       Once per request that wasn't cancelled. from: the language guessed
//       ("vi", "ja", …, or the one Google detected); to: the target used.
//       ok false: error says why ("No answer from Google", "Timed out", …).
//   cancel(id)   no answer for it (stops it if it's running)
//   busy         a request is running; currentId is its id
//   error        the last run's error ("" when it worked)
//   last         the last run's answer: { id, ok, text, translation, from, to, error }
//                (a replaced request never ran: it changes neither)
//   targetFor(text), otherOf(code), guess(text), languageName(code)
//       the same rules, for showing which way it goes before asking.
// One request runs at a time; newest wins: a request made while one runs
// waits, and a newer one takes the waiting one's place (the one it
// replaces finishes with ok false, error "Replaced"). So a search field
// can ask on every key and only the last text is translated after the
// running one. A run gives up after 20 s; text past 4500 characters is
// left out.
//
// Tests: MINE_TRANSLATE_DRYRUN=1 (the command is logged, not run; the
// answer, 100 ms later, is "[<to>] <text>"), MINE_TRANSLATE_CMD (the
// program run instead of curl, given the same arguments and the text on
// stdin).
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_TRANSLATE_DRYRUN") === "1"
    readonly property string program: Quickshell.env("MINE_TRANSLATE_CMD") || "curl"
    readonly property string endpoint: "https://clients5.google.com/translate_a/t"
    readonly property int maxLength: 4500
    readonly property int timeout: 20000

    property bool busy: false
    property string currentId: ""
    property string error: ""
    property var last: null

    signal finished(string id, bool ok, string translation, string from, string to, string error)

    // ---- Which way ----------------------------------------------------------------------------
    function targetFor(text) {
        return Lang.targetFor(text, Style.translatePair);
    }
    function otherOf(code) {
        return Lang.otherOf(code, Style.translatePair);
    }
    function guess(text) {
        return Lang.guess(text);
    }
    function languageName(code) {
        return Lang.languageName(code);
    }

    // ---- Asking -------------------------------------------------------------------------------
    property var job: null              // running: { id, text, from, to }
    property var queued: null           // waiting for it

    function request(id, text, target) {
        let t = String(text ?? "").trim();
        if (t === "")
            return false;
        if (t.length > maxLength)
            t = t.substring(0, maxLength);
        const to = target && target !== "auto" ? target : targetFor(t);
        const ask = { id: String(id), text: t, from: guess(t), to: to };
        if (busy) {
            if (queued)
                answer(queued, false, "", "Replaced", false);
            queued = ask;
            return true;
        }
        run(ask);
        return true;
    }

    function cancel(id) {
        if (queued?.id === String(id))
            queued = null;
        if (job?.id !== String(id))
            return;
        job.cancelled = true;
        if (proc.running) {
            proc.running = false;       // → onExited, which says nothing for it
        } else {
            fakeAnswer.stop();
            done(false, "", "Cancelled");
        }
    }

    function run(ask) {
        job = ask;
        currentId = ask.id;
        busy = true;
        // https only, redirects too; the text is read from stdin (q@-) and
        // added to the address by curl (-G), encoded.
        const url = endpoint + "?client=dict-chrome-ex&sl=auto&tl=" + encodeURIComponent(ask.to);
        const command = [program, "-fsS", "--proto", "=https", "--proto-redir", "=https",
                         "--max-time", String(Math.round(timeout / 1000)), "--max-filesize", "2000000",
                         "-G", "--data-urlencode", "q@-", "--", url];
        if (dryRun) {
            console.log("translate (dry run):", JSON.stringify(command), "stdin:", ask.text.length, "characters");
            fakeAnswer.restart();
            return;
        }
        // Exit 127 when it isn't installed (a program that can't start
        // wouldn't say so otherwise).
        proc.command = ["sh", "-c", 'command -v "$0" >/dev/null || exit 127; exec "$0" "$@"'].concat(command);
        proc.input = ask.text;
        proc.stdinEnabled = true;
        proc.running = true;
        timer.restart();
    }

    function answer(ask, ok, translation, why, ran) {
        const r = { id: ask.id, ok: ok, text: ask.text, translation: translation, from: ask.from, to: ask.to, error: why };
        if (ran) {
            last = r;
            error = why;
        }
        finished(r.id, r.ok, r.translation, r.from, r.to, r.error);
    }

    function done(ok, translation, why) {
        const ask = job;
        job = null;
        timer.stop();
        if (ask && !ask.cancelled)
            answer(ask, ok, translation, why, true);
        busy = false;
        currentId = "";
        if (queued) {
            const nextOne = queued;
            queued = null;
            run(nextOne);
        }
    }

    // Google's answer: [["the translation", "detected language"]] (sl=auto),
    // or ["the translation"] when the source was given.
    function parse(text) {
        try {
            const first = JSON.parse(text)?.[0];
            const pair = Array.isArray(first) ? first : [first];
            return {
                translation: typeof pair[0] === "string" ? pair[0].trim() : "",
                from: typeof pair[1] === "string" ? pair[1] : ""
            };
        } catch (e) {
            return { translation: "", from: "" };
        }
    }

    // The answer once curl has exited AND both its outputs are read
    // (they can end in either order).
    Process {
        id: proc
        property string input: ""
        property bool timedOut: false
        property int code: -1
        property int pending: 0         // exit + stdout + stderr still to come
        onRunningChanged: if (running) {
            code = -1;
            pending = 3;
        }
        // The text, then end of input (curl reads q@- to the end).
        onStarted: {
            write(input);
            input = "";
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            id: out
            onStreamFinished: proc.settle()
        }
        stderr: StdioCollector {
            id: err
            onStreamFinished: proc.settle()
        }
        onExited: exitCode => {
            code = exitCode;
            settle();
        }
        function settle() {
            if (pending <= 0 || --pending > 0)
                return;
            const got = code === 0 ? root.parse(out.text) : { translation: "", from: "" };
            if (timedOut) {
                timedOut = false;
                root.done(false, "", "Timed out");
            } else if (got.translation !== "") {
                if (root.job && root.job.from === "" && /^[A-Za-z-]{2,10}$/.test(got.from))
                    root.job.from = got.from.toLowerCase();
                root.done(true, got.translation, "");
            } else {
                // curl's own words (an address, never the text).
                const why = err.text.trim().split("\n").pop() ?? "";
                if (why !== "")
                    console.warn("translate:", why);
                root.done(false, "", code === 127 ? "curl isn't installed" : "No answer from Google");
            }
        }
    }

    Timer {
        id: timer
        interval: root.timeout
        onTriggered: {
            if (proc.running) {
                proc.timedOut = true;
                proc.running = false;
            }
        }
    }

    Timer {
        id: fakeAnswer
        interval: 100
        onTriggered: root.done(true, "[" + root.job.to + "] " + root.job.text, "")
    }
}
