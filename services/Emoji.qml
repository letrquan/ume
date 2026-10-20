pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The launcher's emoji (type ":", then a name: ":fire", ":thumbs").
// Names, keywords and groups come from GTK's emoji chooser
// (services/emoji.json, made by scripts/make-emoji.py), read the first time
// ":" is typed. Picking one copies it; the ones you pick come first next
// time (~/.local/state/mine-shell/emoji-recent.json).
//
// MINE_EMOJI_STATE (tests): another file for the recent ones.
Singleton {
    id: root

    // [{ e: "🔥", name: "fire", words: [...name words], keys: [...keywords], group, i }]
    property var list: []
    property var groups: []
    // Picked emoji, most recent first.
    property var recent: []
    readonly property int keep: 24
    readonly property bool loaded: list.length > 0

    property bool wanted: false
    function load() {
        wanted = true;
    }

    // Results for the launcher (without the ":"): the recent ones first when
    // nothing is typed, else the best matches.
    function search(term) {
        const q = term.trim().toLowerCase();
        if (q === "") {
            const seen = new Set(recent);
            const first = recent.map(e => list.find(x => x.e === e)).filter(x => x);
            return first.concat(list.filter(x => !seen.has(x.e))).map(result);
        }
        const parts = q.split(/\s+/);
        const scored = [];
        for (const x of list) {
            let s = 0;
            for (const p of parts) {
                const one = score(x, p);
                if (one === 0) {
                    s = 0;
                    break;
                }
                s += one;
            }
            if (s > 0) {
                // Short names first: "red heart" before "heart with arrow".
                s = Math.max(1, s - 3 * x.words.length);
                if (x.name === q)
                    s += 100;
                if (recent.includes(x.e))
                    s += 15;
                if (popular.includes(x.e))
                    s += 5;
                scored.push({ s: s, x: x });
            }
        }
        scored.sort((a, b) => b.s - a.s || a.x.i - b.x.i);
        return scored.map(o => result(o.x));
    }

    // The ones most people mean: a nudge up when they match.
    readonly property var popular: ["❤️", "👍", "😂", "🔥", "😭", "🙏", "😊", "🥰", "😍", "✨", "🎉", "👀", "💀", "🤣",
        "😅", "🥺", "😢", "👌", "💯", "✅", "😎", "🤔", "🙌", "👏", "😁", "😉", "🤗", "😘", "💕", "🙂", "⭐", "☕"]

    // One word: in the name beats in the keywords; the start of a word
    // beats the middle.
    function score(x, p) {
        if (x.words.some(w => w === p))
            return 50;
        if (x.words.some(w => w.startsWith(p)))
            return 40;
        if (x.keys.some(w => w === p))
            return 30;
        if (x.keys.some(w => w.startsWith(p)))
            return 20;
        if (x.name.includes(p))
            return 10;
        return 0;
    }

    function result(x) {
        return { kind: "emoji", title: x.e, subtitle: x.name, group: groups[x.group] ?? "", value: x.e };
    }

    // Copy it (the launcher closes) and remember it.
    function pick(e) {
        recent = [e].concat(recent.filter(x => x !== e)).slice(0, keep);
        recentFile.setText(JSON.stringify({ recent: recent }) + "\n");
        Apps.detached(["wl-copy", e]);
    }

    FileView {
        id: dataFile
        path: root.wanted ? Qt.resolvedUrl("emoji.json").toString().replace(/^file:\/\//, "") : ""
        printErrors: false

        onLoaded: {
            let data;
            try {
                data = JSON.parse(text());
            } catch (e) {
                console.warn("emoji: can't read emoji.json");
                return;
            }
            root.groups = data.groups ?? [];
            root.list = (data.emoji ?? []).map((x, i) => ({
                e: x[0],
                name: x[1].toLowerCase(),
                words: x[1].toLowerCase().replace(/[:,]/g, " ").split(/\s+/).filter(w => w !== ""),
                keys: x[2] === "" ? [] : x[2].split(" "),
                group: x[3],
                i: i
            }));
        }
    }

    readonly property string recentPath: Quickshell.env("MINE_EMOJI_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/emoji-recent.json")
    FileView {
        id: recentFile
        path: root.recentPath
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                root.recent = JSON.parse(text()).recent ?? [];
            } catch (e) {
                root.recent = [];
            }
        }
    }
}
