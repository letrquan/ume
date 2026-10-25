pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.common
import "lyrics.js" as Lyr

// Song lyrics, from lrclib.net (free, no account): under the song in the
// Now Playing card, the line being sung in the bar's middle island, and
// that line and the next in the desktop's music card.
//
// One lookup per song, and only while it's wanted: the card is open, the
// bar shows lines and the song plays, or the desktop's music card is there
// (it shows the song paused too). It asks /api/get with the song's
// artist, title, album and length (that's all lrclib gets), then
// /api/search with a cleaned-up title; the answer (also "none") is saved
// in ~/.cache/mine-shell/lyrics, so a song is looked up once (a "none"
// again after a week). Offline it stays quiet and tries again when the
// song is wanted again 2 minutes later, never in a loop.
//
// Timing: Quickshell works out the player's position from the last one it
// was told (on seeks, play/pause and new songs). One timer waits for the
// next line; nothing ticks between lines. While a line shows, the player's
// own Position is read every 5 s (15 s once it keeps agreeing) to correct
// drift, e.g. a player that doesn't say when you seek in it. A player
// whose Position doesn't move while playing gets the plain lyrics.
//
// MINE_LYRICS_CACHE=<dir> keeps the saved answers elsewhere (tests).
// MINE_LYRICS_FIXTURE=<dir> (tests): no network and no cache; a song's
// lyrics are <dir>/<title>.lrc (lyrics.js fixtureName; "#instrumental"
// for an instrumental, missing = none), after MINE_LYRICS_FIXTURE_DELAY ms.
// MINE_LYRICS_API=<url> asks another server (tests: one that's down).
// MINE_LYRICS_DEBUG=1 logs every line change.
Singleton {
    id: root

    readonly property string cacheDir: Quickshell.env("MINE_LYRICS_CACHE")
        || ((Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/mine-shell/lyrics")
    readonly property string fixtureDir: Quickshell.env("MINE_LYRICS_FIXTURE") ?? ""
    readonly property int fixtureDelay: Number(Quickshell.env("MINE_LYRICS_FIXTURE_DELAY") || 0)
    readonly property bool debug: Quickshell.env("MINE_LYRICS_DEBUG") === "1"

    // ---- Which song --------------------------------------------------------------------
    // The player the whole shell shows (common/Players.qml; the card's pick
    // goes there too).
    readonly property var player: Players.active
    readonly property bool playing: player?.isPlaying ?? false

    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
    readonly property string album: player?.trackAlbum ?? ""
    readonly property real duration: (player?.lengthSupported ?? false) ? (player?.length ?? 0) : 0
    // Browsers (YouTube and the like): video titles aren't songs, and they'd
    // go to lrclib.net too, so they're left out unless Style.lyricsBrowsers.
    readonly property bool fromBrowser: /\b(brave|firefox|chromium|chrome|msedge|edge|vivaldi|opera|librewolf|zen|epiphany|falkon|qutebrowser|floorp|waterfox)\b/i
        .test([player?.dbusName ?? "", player?.identity ?? "", player?.desktopEntry ?? ""].join(" "))
    readonly property bool skipped: fromBrowser && !Style.lyricsBrowsers
    // Not a song: nothing to look up (a stream, a long video, a browser).
    readonly property bool lookable: title !== "" && !(duration > 15 * 60) && !skipped
    readonly property string trackId: lookable ? [artist, title, album].join("\n") : ""

    // Bar items showing lines (bar/Media.qml counts itself in), and the
    // desktop's music cards (desktop/MusicCard.qml, one per screen).
    property int barViews: 0
    property int desktopViews: 0
    readonly property bool cardWants: NowPlayingState.open && Style.lyricsInCard
    readonly property bool barWants: Style.lyricsInBar && barViews > 0 && playing
    readonly property bool desktopWants: Style.lyricsOnDesktop && desktopViews > 0
    readonly property bool wanted: Style.lyricsEnabled && trackId !== "" && (cardWants || barWants || desktopWants)

    // ---- What we have -----------------------------------------------------------------
    // "idle" (nothing yet) | "loading" | "synced" | "plain" | "instrumental"
    // | "none" | "offline"
    property string status: "idle"
    // The song these are for (trackId).
    property string forKey: ""
    property var lines: []      // [{ t, text }], text "" = a pause
    property var plain: []      // lines of text, "" between verses
    property string source: ""  // "cache" | "network" | "fixture"
    property real failedAt: 0

    // Timed lines we can follow: the player says where it is.
    readonly property bool current: forKey !== "" && forKey === trackId
    readonly property bool synced: current && status === "synced" && lines.length > 0
        && (player?.positionSupported ?? false) && !stuck
    // Looking the song up (or about to): views may hold what they show.
    readonly property bool pending: Style.lyricsEnabled && trackId !== ""
        && (!current || status === "idle" || status === "loading")
    // The line being sung: -1 before the first.
    property int index: -1
    readonly property string line: synced && index >= 0 ? (lines[index]?.text ?? "") : ""
    // Some line shows somewhere: the card's lyrics, the bar's or the desktop's.
    readonly property bool lineShown: synced && ((NowPlayingState.open && Style.lyricsInCard) || (Style.lyricsInBar && barViews > 0) || desktopWants)

    // ---- Looking it up -------------------------------------------------------------------
    // Checked a moment later (Qt.callLater), once every binding that hangs
    // on the song has caught up: a new song changes title, artist and
    // album one after another.
    onWantedChanged: Qt.callLater(check)
    onTrackIdChanged: {
        index = -1;
        correction = 0;
        tick.stop();
        Qt.callLater(check);
    }

    function check() {
        const here = forKey !== "" && forKey === trackId;
        if (debug)
            console.log("lyrics: check", JSON.stringify(title), "wanted", wanted, "current", here, "status", status);
        if (!wanted)
            return;
        if (here && status === "offline" && Date.now() - failedAt > 120000) {
            settle.restart();
            return;
        }
        if (here && status !== "idle")
            return;
        if (!here) {
            forKey = trackId;
            status = "idle";
            lines = [];
            plain = [];
            source = "";
        }
        // Browsers change title and artist in steps: wait for it to settle.
        settle.restart();
    }

    Timer {
        id: settle
        interval: 400
        onTriggered: root.load()
    }

    // Look up again (Settings, IPC): forgets the saved answer.
    function reload() {
        if (trackId === "")
            return;
        const key = cacheKeyNow();
        delete memo[key];
        memoOrder = memoOrder.filter(k => k !== key);
        forKey = trackId;
        status = "idle";
        lines = [];
        plain = [];
        skipCache = true;
        load();
    }
    property bool skipCache: false

    function cacheKeyNow() {
        return Lyr.cacheKey(artist, title, album, duration);
    }

    // What the last few songs got, so going back and forth reads nothing.
    property var memo: ({})
    property var memoOrder: []
    function remember(key, entry) {
        memo[key] = entry;
        memoOrder = memoOrder.filter(k => k !== key).concat([key]);
        while (memoOrder.length > 40)
            delete memo[memoOrder.shift()];
    }

    function load() {
        if (debug)
            console.log("lyrics: load", JSON.stringify(title), "wanted", wanted, "same", forKey === trackId, "fetching", fetch.running);
        // Not wanted any more: check() asks again once it is.
        if (!wanted || forKey !== trackId)
            return;
        if (fetch.running) {
            fetch.queued = true;
            return;
        }
        status = "loading";
        const key = cacheKeyNow();
        if (fixtureDir !== "") {
            skipCache = false;
            fixtureWait.key = key;
            fixtureWait.forKey = forKey;
            fixtureWait.restart();
            return;
        }
        if (!skipCache && memo[key]) {
            apply(forKey, memo[key], "cache");
            return;
        }
        reader.forKey = forKey;
        reader.key = key;
        reader.want = { artist: artist, title: title, album: album, duration: duration };
        const path = cacheDir + "/" + key + ".json";
        if (skipCache) {
            skipCache = false;
            ask(forKey, key, reader.want);
        } else if (reader.path === path) {
            reader.reload();
        } else {
            reader.path = path;
        }
    }

    // A saved answer.
    FileView {
        id: reader
        property string forKey: ""
        property string key: ""
        property var want: null
        printErrors: false

        onLoaded: {
            let entry = null;
            try {
                entry = JSON.parse(text());
            } catch (e) {}
            // "None" answers are asked again after a week.
            if (!entry || entry.v !== 1 || (!entry.found && Date.now() - entry.at > 7 * 86400000)) {
                root.ask(forKey, key, want);
                return;
            }
            root.remember(key, entry);
            root.apply(forKey, entry, "cache");
        }
        onLoadFailed: root.ask(forKey, key, want)
    }

    // Tests: lyrics from files.
    Timer {
        id: fixtureWait
        property string key: ""
        property string forKey: ""
        interval: Math.max(1, root.fixtureDelay)
        onTriggered: {
            fixture.forKey = forKey;
            const path = root.fixtureDir + "/" + Lyr.fixtureName(root.title) + ".lrc";
            if (fixture.path === path)
                fixture.reload();
            else
                fixture.path = path;
        }
    }
    FileView {
        id: fixture
        property string forKey: ""
        printErrors: false
        onLoaded: {
            const t = text();
            root.apply(forKey, t.trim() === "#instrumental"
                ? { v: 1, found: true, instrumental: true, synced: null, plain: null }
                : { v: 1, found: true, instrumental: false, synced: t, plain: null }, "fixture");
        }
        onLoadFailed: root.apply(forKey, { v: 1, found: false }, "fixture")
    }

    // ---- lrclib ---------------------------------------------------------------------------
    // MINE_LYRICS_API (tests): another server, e.g. one that's down.
    readonly property string api: Quickshell.env("MINE_LYRICS_API") || "https://lrclib.net/api/"
    readonly property var curl: ["curl", "-fsS", "-m", "10", "-A", "mine-shell/1.0 (personal Quickshell desktop)", "--"]

    function ask(forKey, key, want) {
        fetch.forKey = forKey;
        fetch.key = key;
        fetch.want = want;
        fetch.stage = "get";
        const q = ["artist_name=" + encodeURIComponent(want.artist), "track_name=" + encodeURIComponent(want.title)];
        if (want.album !== "")
            q.push("album_name=" + encodeURIComponent(want.album));
        if (want.duration > 0)
            q.push("duration=" + Math.round(want.duration));
        start(api + "get?" + q.join("&"));
    }

    function search() {
        fetch.stage = "search";
        const w = fetch.want;
        const q = ["track_name=" + encodeURIComponent(Lyr.cleanTitle(w.title))];
        const a = Lyr.firstArtist(w.artist);
        if (a !== "")
            q.push("artist_name=" + encodeURIComponent(a));
        start(api + "search?" + q.join("&"));
    }

    function start(url) {
        fetch.out = "";
        fetch.code = -1;
        fetch.parts = 0;
        fetch.command = curl.concat([url]);
        fetch.running = true;
    }

    Process {
        id: fetch
        property string forKey: ""
        property string key: ""
        property var want: null
        property string stage: ""
        property string out: ""
        property int code: -1
        property int parts: 0
        property bool queued: false

        stdout: StdioCollector {
            onStreamFinished: {
                fetch.out = text;
                fetch.part();
            }
        }
        onExited: (code, status) => {
            fetch.code = code;
            fetch.part();
        }
        // Both the answer and the exit code are in.
        function part() {
            if (++parts === 2)
                root.answered();
        }
    }

    function answered() {
        const f = fetch;
        let data = null;
        try {
            data = f.code === 0 ? JSON.parse(f.out) : null;
        } catch (e) {}
        let entry = null;
        if (f.stage === "get") {
            if (f.code === 0 && data && typeof data === "object" && !Array.isArray(data))
                entry = entryFrom(data);
            else if (f.code === 22) {
                // Not there under that exact name: search.
                search();
                return;
            }
        } else if (f.stage === "search") {
            if (f.code === 0 && Array.isArray(data)) {
                const best = Lyr.choose(data, f.want);
                entry = best ? entryFrom(best) : { v: 1, at: Date.now(), found: false };
            }
        }
        if (entry === null) {
            // Offline, or lrclib is down: say so quietly; no retry here.
            console.log("lyrics: can't reach lrclib (curl exit " + f.code + ")");
            if (f.forKey === forKey) {
                status = "offline";
                failedAt = Date.now();
            }
        } else {
            remember(f.key, entry);
            save(f.key, entry);
            apply(f.forKey, entry, "network");
        }
        if (f.queued) {
            f.queued = false;
            Qt.callLater(load);
        }
    }

    function entryFrom(r) {
        const synced = typeof r.syncedLyrics === "string" && r.syncedLyrics.trim() !== "" ? r.syncedLyrics : null;
        const plain = typeof r.plainLyrics === "string" && r.plainLyrics.trim() !== "" ? r.plainLyrics : null;
        return { v: 1, at: Date.now(), found: synced !== null || plain !== null || r.instrumental === true,
                 instrumental: r.instrumental === true && synced === null && plain === null,
                 synced: synced, plain: plain, id: Number(r.id) || 0 };
    }

    // Saved as <key>.json (key: lyrics.js cacheKey, letters, digits, -).
    function save(key, entry) {
        if (!madeDir) {
            madeDir = true;
            Quickshell.execDetached(["mkdir", "-p", "--", cacheDir]);
        }
        writer.queue.push({ path: cacheDir + "/" + key + ".json", text: JSON.stringify(entry) });
        writeSoon.restart();
    }
    property bool madeDir: false
    // A moment later, so the folder is there.
    Timer {
        id: writeSoon
        interval: 300
        onTriggered: {
            while (writer.queue.length > 0) {
                const w = writer.queue.shift();
                writer.path = w.path;
                writer.setText(w.text);
            }
        }
    }
    FileView {
        id: writer
        property var queue: []
        preload: false
        atomicWrites: true
        printErrors: false
    }

    function apply(key, entry, from) {
        if (key !== forKey)
            return;   // an older song's answer (saved, not shown)
        const parsed = Lyr.parse(entry.synced ?? "");
        lines = parsed.synced;
        plain = entry.plain ? Lyr.plainLines(entry.plain) : parsed.plain;
        source = from;
        status = !entry.found ? "none"
            : entry.instrumental ? "instrumental"
            : lines.length > 0 ? "synced"
            : plain.length > 0 ? "plain"
            : "none";
        console.log("lyrics:", status, "for", JSON.stringify(title), "(" + (lines.length || plain.length) + " lines, " + from + ")");
        sync();
    }

    // ---- Following the song -------------------------------------------------------------
    // Seconds: what the player itself says minus what Quickshell works out
    // (drift reads below); 0 most of the time.
    property real correction: 0
    function clock() {
        return (player?.position ?? 0) + correction + Style.lyricsOffset;
    }

    function sync() {
        if (!synced) {
            tick.stop();
            if (index !== -1)
                index = -1;
            return;
        }
        const t = clock();
        const i = Lyr.indexAt(lines, t);
        if (i !== index) {
            index = i;
            if (debug)
                console.log("lyrics: line", i, "at", t.toFixed(2), JSON.stringify(lines[i]?.text ?? ""));
        }
        if (playing && i + 1 < lines.length) {
            const rate = (player?.rate ?? 1) > 0 ? player.rate : 1;
            tick.interval = Math.max(16, Math.ceil((lines[i + 1].t - t) / rate * 1000) + 8);
            tick.restart();
        } else {
            tick.stop();
        }
    }

    // Waits for the next line.
    Timer {
        id: tick
        onTriggered: root.sync()
    }

    onSyncedChanged: sync()
    // Paused or playing again: the line stays as it is until the player
    // says where it is (Quickshell asks it then; until the answer its
    // position is off, counting the pause as played on resume).
    onPlayingChanged: {
        tick.stop();
        if (playing)
            resumed.restart();
    }
    // In case no answer comes.
    Timer {
        id: resumed
        interval: 300
        onTriggered: root.sync()
    }
    onPlayerChanged: {
        correction = 0;
        lastAt = 0;
        sync();
    }
    Connections {
        target: Style
        function onLyricsOffsetChanged() {
            root.sync();
        }
    }

    // Quickshell says the position changed: a seek, play/pause or a new
    // song (a real jump), or just someone asking it to update (no jump).
    // Read a moment later (Qt.callLater): on a seek Quickshell first
    // reports the new place plus the time since its previous update, and
    // only then the right one.
    property real lastPos: 0
    property real lastAt: 0
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onPositionChanged() {
            Qt.callLater(root.positionMoved);
        }
        function onRateChanged() {
            Qt.callLater(root.sync);
        }
    }
    function positionMoved() {
        const p = player?.position ?? 0;
        const now = Date.now();
        if (lastAt > 0) {
            const expect = lastPos + (playing ? (now - lastAt) / 1000 * ((player?.rate ?? 1) || 1) : 0);
            // The player told Quickshell where it is: our correction is stale.
            if (Math.abs(p - expect) > 0.25)
                correction = 0;
        }
        lastPos = p;
        lastAt = now;
        resumed.stop();
        sync();
    }

    // ---- Drift reads ---------------------------------------------------------------------
    // Players whose Position doesn't move while playing (by D-Bus name).
    property var stuckPlayers: ({})
    readonly property bool stuck: stuckPlayers[player?.dbusName ?? ""] === true
    property int agreeing: 0
    property real lastRead: -1
    property real lastReadAt: 0

    Timer {
        running: root.lineShown && root.playing && (root.player?.dbusName ?? "") !== ""
        interval: root.agreeing >= 3 ? 15000 : 5000
        repeat: true
        triggeredOnStart: true
        onRunningChanged: {
            root.lastRead = -1;
            root.agreeing = 0;
        }
        onTriggered: {
            if (probe.running)
                return;
            probe.command = ["busctl", "--user", "get-property", root.player.dbusName,
                             "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Position"];
            probe.running = true;
        }
    }

    Process {
        id: probe
        stdout: StdioCollector {
            onStreamFinished: root.probed(text)
        }
    }

    function probed(text) {
        const m = /^x\s+(-?\d+)/.exec(String(text).trim());
        if (!m || !playing || !player)
            return;
        const said = Number(m[1]) / 1e6;
        const now = Date.now();
        // The same value twice, 3 s apart, while playing: it doesn't move.
        if (lastRead >= 0 && said === lastRead && now - lastReadAt >= 3000) {
            const s = Object.assign({}, stuckPlayers);
            s[player.dbusName] = true;
            stuckPlayers = s;
            console.log("lyrics:", player.identity, "doesn't say where it is; plain lyrics");
            return;
        }
        lastRead = said;
        lastReadAt = now;
        // Exactly 0 while playing: likely one that never moves; the next
        // read tells (no correction from it meanwhile).
        if (said === 0)
            return;
        const diff = said - (player.position ?? 0);
        const fix = Math.abs(diff) > 0.25 ? diff : 0;
        agreeing = Math.abs(diff - correction) < 0.25 ? agreeing + 1 : 0;
        if (Math.abs(fix - correction) > 0.05) {
            console.log("lyrics: drift", diff.toFixed(2), "s, corrected");
            correction = fix;
            sync();
        }
    }

    // A player that went away: it may come back fixed.
    Connections {
        target: Mpris.players
        function onValuesChanged() {
            const names = Mpris.players.values.map(p => p.dbusName);
            const s = {};
            for (const k in root.stuckPlayers)
                if (names.includes(k))
                    s[k] = true;
            root.stuckPlayers = s;
        }
    }

    // ---- For the views -------------------------------------------------------------------
    // Where to seek for line i (the views seek the player).
    function timeOf(i) {
        return Math.max(0, (lines[i]?.t ?? 0) - Style.lyricsOffset + 0.02);
    }

    function describe() {
        return JSON.stringify({ status: status, synced: synced, index: index, line: line, lines: lines.length,
                                plain: plain.length, source: source, title: title, player: player?.identity ?? "",
                                correction: Math.round(correction * 100) / 100, stuck: stuck });
    }
}
