pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The album cover's colors while music plays (Style.artColors): the shell's
// accent colors (or all of them, Style.artColorsStrength) glide to the
// cover's, and back to the wallpaper's Style.artColorsHold seconds after the
// music stops or pauses.
//
// matugen reads the cover exactly as Wallpaper.qml reads the wallpaper (same
// color style, light or dark as Theme says, same -c config: it only prints
// JSON, it never writes a file). The result only goes to Colors.art, so GTK
// apps, mango's borders, foot and the lock keep the wallpaper's colors.
//
// Covers on the web are downloaded once to $XDG_RUNTIME_DIR/mine-shell/art
// (the last 30 kept); palettes are remembered while the shell runs.
// MINE_ART_DIR (tests): another folder for the downloads.
Singleton {
    id: root

    readonly property bool enabled: Style.artColors

    // The player the whole shell shows (common/Players.qml).
    readonly property var player: Players.active
    readonly property bool playing: player?.isPlaying ?? false
    readonly property string artUrl: Players.art(player)

    // What should show: this cover, in this mode and color style ("" = the
    // wallpaper's colors).
    readonly property string mode: Theme.dark ? "dark" : "light"
    readonly property string key: enabled && playing && artUrl !== "" ? keyFor(artUrl) : ""
    function keyFor(url) {
        return url !== "" ? url + "|" + mode + "|" + Style.wallpaperScheme : "";
    }
    // What shows now.
    property string shown: ""
    readonly property bool active: shown !== ""

    readonly property string artDir: Quickshell.env("MINE_ART_DIR")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/mine-shell/art")

    // key -> { role: "#hex" } for every role, worked out once each.
    property var palettes: ({})
    property var paletteKeys: []

    // Only the accent families with "accent"; everything with "full".
    readonly property var accentRoles: [
        "primary", "textOnPrimary", "primaryContainer", "textOnPrimaryContainer",
        "secondary", "textOnSecondary", "secondaryContainer", "textOnSecondaryContainer",
        "tertiary", "textOnTertiary", "tertiaryContainer", "textOnTertiaryContainer"
    ]

    function show(k) {
        const all = palettes[k];
        if (!all)
            return;
        const out = {};
        for (const role of (Style.artColorsStrength === "full" ? Object.keys(all) : accentRoles))
            if (all[role])
                out[role] = all[role];
        shown = k;
        Colors.art = out;
    }
    function clear() {
        hold.stop();
        if (shown === "")
            return;
        shown = "";
        Colors.art = {};
    }

    // A track change (or play/pause) settles first: skipping through songs
    // doesn't recolor for each one.
    onKeyChanged: settle.restart()
    onEnabledChanged: if (!enabled) clear()
    Connections {
        target: Style
        function onArtColorsStrengthChanged() {
            if (root.active)
                root.show(root.shown);
        }
    }
    Timer {
        id: settle
        interval: 600
        onTriggered: root.update()
    }
    // After the music stops: the wallpaper's colors again.
    Timer {
        id: hold
        interval: Math.max(0, Style.artColorsHold) * 1000
        onTriggered: root.clear()
    }

    function update() {
        if (key === "") {
            if (active && !hold.running)
                hold.restart();
            return;
        }
        hold.stop();
        if (palettes[key]) {
            show(key);
            return;
        }
        fetch(artUrl, key);
    }

    function fetch(url, k) {
        if (url.startsWith("file://")) {
            // Any app names its cover: only an absolute path is read (one
            // starting with "-" would reach matugen as an option), and a
            // broken %-escape is skipped.
            let path = "";
            try {
                path = decodeURIComponent(url.substring(7));
            } catch (e) {}
            if (path.startsWith("/"))
                read(path, k);
        } else if (/^https?:\/\//.test(url))
            download(url, k);
        // Anything else (data: urls…): the wallpaper's colors stay.
    }

    // ---- Any cover, for the Now Playing card -----------------------------------------
    // The palette of `url` (any player, playing or not, art colors on or
    // off), or null while it's being worked out: paletteReady(key) says when
    // it's there. It never touches Colors.art.
    signal paletteReady(string key)
    property var asked: ({})
    function paletteFor(url) {
        const k = keyFor(url);
        if (k === "")
            return null;
        if (palettes[k])
            return palettes[k];
        if (!asked[k]) {
            asked[k] = true;
            fetch(url, k);
        }
        return null;
    }

    // ---- The cover -------------------------------------------------------------------
    // One download at a time; the newest wanted one waits.
    property var nextDownload: null
    function download(url, k) {
        if (fetcher.running) {
            nextDownload = { url: url, key: k };
            return;
        }
        fetcher.file = artDir + "/" + Qt.md5(url) + ".img";
        fetcher.forKey = k;
        fetcher.command = ["sh", "-c",
            'mkdir -p "$1" || exit 1; [ -s "$2" ] && exit 0; '
            + 'curl -sfL --proto =https --proto-redir =https --max-time 15 --max-filesize 20000000 -o "$2.part" -- "$3" && mv "$2.part" "$2" || { rm -f "$2.part"; exit 1; }; '
            + 'ls -t "$1" | tail -n +31 | while read -r f; do rm -f "$1/$f"; done',
            "sh", artDir, fetcher.file, url];
        fetcher.running = true;
    }
    Process {
        id: fetcher
        property string file: ""
        property string forKey: ""
        onExited: code => {
            if (code === 0)
                root.read(file, forKey);
            else
                console.log("art colors: couldn't get the cover");
            if (root.nextDownload) {
                const n = root.nextDownload;
                root.nextDownload = null;
                root.download(n.url, n.key);
            }
        }
    }

    // ---- Its colors --------------------------------------------------------------------
    property var nextRead: null
    function read(image, k) {
        if (matugen.running) {
            nextRead = { image: image, key: k };
            return;
        }
        matugen.forKey = k;
        matugen.command = ["matugen", "image", image, "--dry-run", "-j", "hex",
                           "-m", k.split("|").slice(-2)[0], "-t", k.split("|").slice(-1)[0],
                           "--source-color-index", "0",
                           "-c", Quickshell.shellDir + "/matugen/config.toml"];
        matugen.running = true;
    }
    Process {
        id: matugen
        property string forKey: ""
        stdout: StdioCollector {
            onStreamFinished: root.keep(matugen.forKey, text)
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("art colors: matugen:", text.trim())
        }
        onExited: {
            if (root.nextRead) {
                const n = root.nextRead;
                root.nextRead = null;
                root.read(n.image, n.key);
            }
        }
    }
    function keep(k, json) {
        let colors;
        try {
            colors = JSON.parse(json).colors;
        } catch (e) {
            console.log("art colors: matugen gave no colors for the cover");
            return;
        }
        const out = {};
        for (const name in Wallpaper.roles) {
            const hex = colors[Wallpaper.roles[name]]?.default?.color;
            if (hex)
                out[name] = hex;
        }
        palettes[k] = out;
        delete asked[k];
        paletteKeys = paletteKeys.filter(x => x !== k).concat([k]);
        while (paletteKeys.length > 40)
            delete palettes[paletteKeys.shift()];
        paletteReady(k);
        // Still the one wanted (the song may have changed meanwhile).
        if (k === key)
            show(k);
    }
}
