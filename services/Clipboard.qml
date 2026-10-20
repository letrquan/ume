pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Clipboard history, kept by cliphist (~/.cache/cliphist/db, also has your
// older history). While the shell runs, everything you copy (text and
// pictures) is stored there by two `wl-paste --watch`. Secrets are left
// out (Style.clipSkipSecrets): copied text goes through
// scripts/clip-store.sh, which drops API keys, tokens, private keys and the
// codes your phone's notifications just showed; cliphist itself drops what
// a password manager marks as secret.
// Choosing an entry copies it back and pastes it into the app you were in.
//
// Entry: { id, text, image: bool, imageInfo ("png 896x515"), thumb (file url) }
//
// Picture thumbnails are cached as <thumbDir>/<id>.png (or .jpg); forgetting
// an entry deletes its thumbnail, Clear deletes them all.
//
// MINE_CLIP_DRYRUN=1 (tests): no watchers, nothing copied, pasted or deleted;
// MINE_CLIP_THUMBS: where picture thumbnails go.
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_CLIP_DRYRUN") === "1"
    readonly property string thumbDir: Quickshell.env("MINE_CLIP_THUMBS") || (Quickshell.env("HOME") + "/.cache/mine-shell/clip")

    property var entries: []
    property bool loading: false

    // Apps that paste with Ctrl+Shift+V.
    readonly property var terminals: ["foot", "footclient", "com.mitchellh.ghostty", "kitty", "Alacritty", "alacritty",
                                      "org.wezfurlong.wezterm", "org.kde.konsole", "org.gnome.Terminal", "org.gnome.Console", "xterm"]

    function refresh() {
        if (lister.running)
            return;
        loading = true;
        lister.running = true;
    }

    // Copy it back; then (pasteInto set) paste it into that app.
    function use(entry, paste) {
        if (!/^\d+$/.test(entry.id))
            return;
        const app = ClipboardState.pasteInto;
        if (dryRun) {
            console.log("clipboard (dry run): copy", entry.id, paste ? "and paste into " + app : "");
            return;
        }
        // Copying an old one back isn't news for the live activity.
        Activities.expectCopy();
        const keys = terminals.includes(app) ? "-M ctrl -M shift v -m shift -m ctrl" : "-M ctrl v -m ctrl";
        // Wait for the history to close and the app to get the keyboard back.
        const pasteCmd = paste && Style.clipAutoPaste ? " && sleep 0.25 && wtype " + keys : "";
        Quickshell.execDetached(["sh", "-c", "cliphist decode " + entry.id + " | wl-copy" + pasteCmd]);
    }

    function remove(entry) {
        if (!/^\d+$/.test(entry.id))
            return;
        entries = entries.filter(e => e.id !== entry.id);
        if (dryRun) {
            console.log("clipboard (dry run): delete", entry.id);
            return;
        }
        // Out of cliphist, then its thumbnail if it was a picture.
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\t\\n" "$1" | cliphist delete; rm -f -- "$2/$1.png" "$2/$1.jpg"',
            "remove", entry.id, thumbDir]);
    }

    function wipe() {
        entries = [];
        if (dryRun) {
            console.log("clipboard (dry run): wipe");
            return;
        }
        // All thumbnails too, then the folder (makeThumbs makes it again).
        // Only the <id>.png/.jpg files we make: nothing else in it is touched.
        Quickshell.execDetached(["sh", "-c", 'cliphist wipe; rm -f -- "$1"/[0-9]*.png "$1"/[0-9]*.jpg; rmdir -- "$1" 2>/dev/null; true',
            "wipe", thumbDir]);
    }

    // A picture's thumbnail, made once (decoded from cliphist into the cache).
    function thumbFor(entry) {
        const ext = entry.imageInfo.startsWith("jpeg") || entry.imageInfo.startsWith("jpg") ? "jpg" : "png";
        return root.thumbDir + "/" + entry.id + "." + ext;
    }

    Process {
        id: lister
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    const id = line.slice(0, tab);
                    const preview = line.slice(tab + 1);
                    const m = /^\[\[ binary data .* (\w+) (\d+x\d+) \]\]$/.exec(preview);
                    out.push({ id: id, text: preview, image: m !== null, imageInfo: m ? m[1] + " " + m[2] : "" });
                }
                root.entries = out;
                root.loading = false;
                root.makeThumbs();
            }
        }
    }

    // Decode the pictures we haven't cached yet (newest first, a few).
    function makeThumbs() {
        const want = entries.filter(e => e.image).slice(0, 24).map(e => e.id + ":" + thumbFor(e));
        if (want.length === 0 || thumbs.running)
            return;
        thumbs.command = ["sh", "-c",
            'mkdir -p "$1"; shift; for x in "$@"; do id=${x%%:*}; f=${x#*:}; [ -s "$f" ] || cliphist decode "$id" > "$f"; done; echo done',
            "thumbs", thumbDir].concat(want);
        thumbs.running = true;
    }
    property int thumbsVersion: 0
    Process {
        id: thumbs
        stdout: StdioCollector {
            onStreamFinished: root.thumbsVersion++
        }
    }

    // Keep copied things alive after the app they came from closes, if
    // wl-clip-persist is installed (otherwise Noctalia does it).
    Process {
        id: persist
        running: !root.dryRun
        command: ["sh", "-c", "command -v wl-clip-persist >/dev/null || exit 127; exec wl-clip-persist --clipboard regular"]
        // 127 from sh = not installed: nothing to do. Anything else: it
        // died, start it again (a few times at most, each wait longer).
        onExited: code => {
            if (root.dryRun || code === 127 || ++root.persistCrashes > 5)
                return;
            restartPersist.interval = 3000 * root.persistCrashes;
            restartPersist.restart();
        }
    }
    property int persistCrashes: 0
    Timer {
        id: restartPersist
        onTriggered: persist.running = true
    }

    // Keep the history: everything copied (text, then pictures). Text
    // through clip-store.sh, unless secrets may be kept.
    // `mine stop` cleans up these command lines after a crash: keep its
    // pkill pattern matching them.
    Process {
        id: watchText
        running: !root.dryRun
        command: Style.clipSkipSecrets
            ? ["wl-paste", "--type", "text", "--watch", "sh", Quickshell.shellDir + "/scripts/clip-store.sh"]
            : ["wl-paste", "--type", "text", "--watch", "cliphist", "store"]
        // The setting changed: end it (if it runs yet), so it starts again
        // with the other command.
        onCommandChanged: signal(15)
        onExited: restartWatch.start()
    }
    Process {
        id: watchImages
        running: !root.dryRun
        command: ["wl-paste", "--type", "image", "--watch", "cliphist", "store"]
        onExited: restartWatch.start()
    }
    Timer {
        id: restartWatch
        interval: 3000
        onTriggered: {
            if (root.dryRun)
                return;
            watchText.running = true;
            watchImages.running = true;
        }
    }
}
