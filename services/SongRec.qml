pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.common

// Name that song (the control center's "song" tile, IPC `song`): songrec
// listens to what the laptop plays (Style.songSource "output": the default
// output's monitor, e.g. alsa_output…Speaker__sink.monitor) or to the
// microphone ("mic": the default input), and asks Shazam. Shazam gets a
// fingerprint of the sound (not the sound itself), every few seconds until
// one is recognised:
//   songrec recognize -j -i <a third of Style.songListenSeconds> -d <device>
// songrec stops by itself only on a match (no match = it keeps listening),
// so the shell stops it after Style.songListenSeconds, plus a few seconds
// for the last answer: three tries, the first after 4 s of sound by default.
// Found: a notification with the title, artist, album and cover (fetched
// over https into $XDG_RUNTIME_DIR, gone at logout) and Copy ("Artist -
// Title"), YouTube and Spotify (a search in the browser).
//
// Tests: MINE_SONGREC (the songrec to run), MINE_SONG_DEVICE (the device
// instead of PipeWire's), MINE_SONG_DRYRUN=1 (notification, copy, browser
// and cover download printed, not done), MINE_SONG_COVERS (where covers go).
Singleton {
    id: root

    readonly property string songrec: Quickshell.env("MINE_SONGREC") || "songrec"
    readonly property bool dryRun: Quickshell.env("MINE_SONG_DRYRUN") === "1"
    readonly property string coverDir: Quickshell.env("MINE_SONG_COVERS") || Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

    property bool listening: false
    property string source: ""          // "output" | "mic", while listening
    property int elapsed: 0             // s
    property string message: ""         // what the tile says after (found / no match / why not)
    property var result: null           // { title, artist, album, cover, url, key }
    readonly property string otherSource: Style.songSource === "mic" ? "output" : "mic"
    readonly property int listenFor: Math.max(6, Style.songListenSeconds)
    readonly property int interval: Math.max(3, Math.round(listenFor / 3))

    readonly property string detail: listening
        ? (elapsed < listenFor ? elapsed + " s" + (source === "mic" ? " · mic" : "") + " · click to stop" : "Waiting for the answer…")
        : message !== "" ? message
        : Style.songSource === "mic" ? "With the microphone" : "What's playing here"

    // The device songrec reads (PulseAudio names, as `songrec recognize -l` lists them).
    function deviceFor(src) {
        const forced = Quickshell.env("MINE_SONG_DEVICE");
        if (forced)
            return forced;
        if (src === "mic")
            return Pipewire.defaultAudioSource?.name ?? "";
        const sink = Pipewire.defaultAudioSink?.name ?? "";
        return sink !== "" ? sink + ".monitor" : "";
    }

    // Click: listen (src "" = Style.songSource); click again: stop.
    function toggle(src) {
        if (listening)
            stop();
        else
            listen(src || Style.songSource);
    }

    function listen(src) {
        // (Or the last one is still on its way out.)
        if (listening || listener.running)
            return;
        const device = deviceFor(src);
        if (device === "") {
            say(src === "mic" ? "No microphone" : "No sound output");
            return;
        }
        source = src;
        elapsed = 0;
        message = "";
        why = "";
        listener.command = [songrec, "recognize", "-j", "-i", String(interval), "-d", device];
        console.log("song: listening to", device, "for", listenFor, "s");
        listening = true;
        listener.running = true;
        ticker.restart();
        cap.restart();
    }

    // You (a second click): nothing more is said.
    function stop() {
        if (!listening)
            return;
        why = "stopped";
        listener.running = false;
        finish();
    }

    property string why: ""             // "stopped" | "time": why songrec was stopped

    function finish() {
        listening = false;
        ticker.stop();
        cap.stop();
    }

    function say(text) {
        message = text;
        forget.restart();
    }
    Timer {
        id: forget
        interval: 20000
        onTriggered: root.message = ""
    }

    Timer {
        id: ticker
        interval: 1000
        repeat: true
        onTriggered: root.elapsed++
    }
    Timer {
        id: cap
        interval: (root.listenFor + 4) * 1000
        onTriggered: {
            root.why = "time";
            listener.running = false;
        }
    }

    Process {
        id: listener

        property bool outDone: false
        property bool exitDone: false
        onStarted: outDone = exitDone = false

        stdout: StdioCollector {
            id: heard
            onStreamFinished: {
                listener.outDone = true;
                root.ended();
            }
        }
        stderr: StdioCollector { id: complaints }
        onExited: {
            exitDone = true;
            root.ended();
        }
    }

    // songrec is done (found, stopped by us, or gave up): once both its
    // output and its exit are in.
    function ended() {
        if (!listener.outDone || !listener.exitDone)
            return;
        listener.outDone = listener.exitDone = false;
        const wasStopped = why === "stopped";
        finish();
        if (wasStopped)
            return;
        const found = parse(heard.text);
        if (found) {
            result = found;
            say("Found: " + found.title);
            console.log("song: found", found.artist, "-", found.title);
            tell(found);
            return;
        }
        const err = complaints.text;
        if (/device not found/i.test(err))
            say("Can't listen to that device");
        else if (/no audio devices/i.test(err))
            say("No sound device");
        else if (/network unreachable/i.test(err))
            say("Offline: Shazam can't be reached");
        else if (why === "time")
            say("No match");
        else
            say("songrec stopped" + (firstLine(err) !== "" ? ": " + firstLine(err) : ""));
        console.log("song:", message);
    }

    // songrec -j prints Shazam's answer (JSON) once it has a match.
    function parse(text) {
        const t = String(text ?? "").trim();
        if (t === "")
            return null;
        let j = null;
        try {
            j = JSON.parse(t);
        } catch (e) {
            // Something else printed too: the last line that is an object.
            const line = t.split("\n").reverse().find(l => l.trim().startsWith("{"));
            try {
                j = line ? JSON.parse(line) : null;
            } catch (e2) {
                j = null;
            }
        }
        const tr = j?.track;
        if (!tr || typeof tr.title !== "string" || tr.title.trim() === "")
            return null;
        const meta = Array.isArray(tr.sections) ? tr.sections.reduce((all, s) => all.concat(Array.isArray(s?.metadata) ? s.metadata : []), []) : [];
        const httpsOnly = u => typeof u === "string" && /^https:\/\/[^\s"'<>]+$/.test(u) ? u : "";
        return {
            title: clean(tr.title),
            artist: clean(tr.subtitle),
            album: clean(meta.find(m => m?.title === "Album")?.text),
            cover: httpsOnly(tr.images?.coverarthq) || httpsOnly(tr.images?.coverart) || httpsOnly(tr.share?.image),
            url: httpsOnly(tr.url) || httpsOnly(tr.share?.href),
            key: String(tr.key ?? "").replace(/[^0-9A-Za-z_-]/g, "").substring(0, 40) || String(Date.now())
        };
    }

    // One line, no control or direction-flipping characters.
    function clean(text) {
        return String(text ?? "").replace(/[\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g, " ")
            .replace(/\s+/g, " ").trim().substring(0, 200);
    }
    function firstLine(text) {
        return clean(String(text ?? "").split("\n").map(l => l.trim()).find(l => l !== "") ?? "").substring(0, 120);
    }
    function markupSafe(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // ---- The notification -------------------------------------------------------------
    function tell(r) {
        if (r.cover === "") {
            send(r, "");
            return;
        }
        const file = coverDir + "/mine-song-" + r.key + ".jpg";
        const cmd = ["curl", "-fsSL", "--proto", "=https", "--max-time", "8", "-o", file, "--", r.cover];
        if (dryRun) {
            console.log("song (dry run):", cmd.join(" "));
            send(r, "");
            return;
        }
        const p = fetcher.createObject(root, { command: cmd, song: r, file: file });
        p.running = true;
    }
    Component {
        id: fetcher

        Process {
            property var song
            property string file
            onExited: code => {
                root.send(song, code === 0 ? file : "");
                destroy();
            }
        }
    }

    function send(r, cover) {
        const body = markupSafe(r.artist + (r.album !== "" ? " · " + r.album : ""));
        const cmd = ["notify-send", "-a", "Name that song", "-i", "audio-x-generic"]
            .concat(cover !== "" ? ["-h", "string:image-path:" + cover] : [])
            .concat(["-A", "copy=Copy", "-A", "youtube=YouTube", "-A", "spotify=Spotify", "--", r.title, body]);
        if (dryRun) {
            console.log("song (dry run):", cmd.join(" "));
            return;
        }
        const p = notice.createObject(root, { command: cmd, song: r });
        p.running = true;
    }

    // notify-send waits while the notification is around and prints the
    // button pressed.
    Component {
        id: notice

        Process {
            property var song
            stdout: SplitParser {
                onRead: line => root.act(line.trim(), song)
            }
            onExited: destroy()
        }
    }

    function searchText(r) {
        return (r.artist !== "" ? r.artist + " " : "") + r.title;
    }
    function act(action, r) {
        if (!r)
            return;
        let cmd = null;
        if (action === "copy")
            cmd = ["wl-copy", "--", (r.artist !== "" ? r.artist + " - " : "") + r.title];
        else if (action === "youtube")
            cmd = ["xdg-open", "https://www.youtube.com/results?search_query=" + encodeURIComponent(searchText(r))];
        else if (action === "spotify")
            cmd = ["xdg-open", "https://open.spotify.com/search/" + encodeURIComponent(searchText(r))];
        if (!cmd)
            return;
        if (dryRun)
            console.log("song (dry run):", cmd.join(" "));
        else
            Quickshell.execDetached(cmd);
    }

    function status() {
        return listening ? "listening " + elapsed + " s" : message !== "" ? message : "idle";
    }
}
