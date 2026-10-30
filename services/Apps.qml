pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "calc.js" as Calc

// What the launcher finds and runs: apps (ranked by how well the name
// matches and how often you open them), settings (the launcher passes them
// in from settings/SettingsSearch.qml: "dock" -> Settings › Dock › …), a
// calculator (2+3*4), a web address to open (github.com) and a web-search
// row. How often each app was opened is kept in
// ~/.local/state/mine-shell/launcher.json.
// What you type first picks another mode (each can be turned off in
// Style.qml / Settings):
//   :fire        emoji (services/Emoji.qml), Enter copies it
//   /invoice ~x  files (services/FileSearch.qml), Enter opens, Ctrl+Enter
//                opens the folder it's in
//   ?weather     the web (Style.webSearchUrl)
//   tr hello     a translation (services/Translator.qml), Enter copies it;
//                "tr ja: hello" picks the language
//
// Result: { kind: "app" | "setting" | "calc" | "web" | "url" | "emoji" | "file"
//                 | "translate" | "hint", title, subtitle, icon, entry, value }
Singleton {
    id: root

    property var counts: ({})
    property int countsVersion: 0

    // MINE_LAUNCHER_DRYRUN=1 / MINE_LAUNCHER_STATE are for testing: nothing
    // is launched, opened or copied, only printed.
    readonly property bool dryRun: Quickshell.env("MINE_LAUNCHER_DRYRUN") === "1"
    readonly property string statePath: Quickshell.env("MINE_LAUNCHER_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/launcher.json")

    readonly property var apps: DesktopEntries.applications.values.filter(a => !a.noDisplay)

    // ---- Modes ----------------------------------------------------------------
    function modeOf(query) {
        const q = query.replace(/^\s+/, "");
        if (Style.launcherEmoji && q.startsWith(":"))
            return "emoji";
        if (Style.launcherFiles && (q.startsWith("/") || q.startsWith("~")))
            return "files";
        if (Style.launcherWeb && q.startsWith("?"))
            return "web";
        if (Style.launcherTranslate && /^tr\s/i.test(q))
            return "translate";
        return "apps";
    }

    // What's typed after the mode's sign.
    function termOf(query) {
        const q = query.replace(/^\s+/, "");
        switch (modeOf(query)) {
        case "emoji":
        case "web":
            return q.slice(1).trim();
        case "files":
            return q.replace(/^[~\/]+/, "").trim();
        case "translate":
            return q.slice(2).trim();
        }
        return q.trim();
    }

    // Called by the launcher when the text changes (searches that run on
    // their own: files, a translation; data read the first time: emoji),
    // and with "" when it closes.
    function prepare(query) {
        const mode = modeOf(query);
        if (mode === "emoji")
            Emoji.load();
        FileSearch.search(mode === "files" ? termOf(query) : "");
        if (mode === "translate")
            translateLater(termOf(query));
        else
            stopTranslating();
    }

    // "Google" for https://www.google.com/search?q=%s
    readonly property string engine: {
        const host = (Style.webSearchUrl.match(/^\w+:\/\/([^\/:?#]+)/)?.[1] ?? "").split(".");
        const word = host.length > 1 ? host[host.length - 2] : (host[0] || "the web");
        const known = { duckduckgo: "DuckDuckGo", google: "Google", bing: "Bing", kagi: "Kagi", startpage: "Startpage",
                        brave: "Brave Search", ecosia: "Ecosia", youtube: "YouTube", wikipedia: "Wikipedia" };
        return known[word] ?? (word.charAt(0).toUpperCase() + word.slice(1));
    }
    function webUrl(text) {
        const u = Style.webSearchUrl;
        return u.includes("%s") ? u.replace("%s", encodeURIComponent(text)) : u + encodeURIComponent(text);
    }
    function webResult(text) {
        return { kind: "web", title: "Search " + engine + " for “" + text + "”", subtitle: "Opens your browser", icon: "travel_explore", value: text };
    }

    // github.com, example.org/page, https://…, localhost:8080; not a file
    // name like notes.md or shell.qml (unless it starts with www.).
    readonly property var fileEndings: ["qml", "js", "ts", "py", "sh", "md", "txt", "json", "conf", "toml", "yaml", "yml",
        "png", "jpg", "jpeg", "gif", "svg", "webp", "pdf", "zip", "gz", "xz", "zst", "tar", "c", "h", "cpp", "rs", "go",
        "lua", "rb", "java", "css", "html", "htm", "xml", "log", "ini", "cfg", "desktop", "service", "mp3", "mp4", "mkv",
        "webm", "wav", "flac", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "csv", "kt", "fish", "zsh", "nix", "lock"]
    function urlOf(text) {
        const t = text.trim();
        if (t === "" || /\s/.test(t))
            return "";
        if (/^https?:\/\/\S+$/i.test(t))
            return t;
        if (/^localhost(:\d+)?(\/\S*)?$/i.test(t))
            return "http://" + t;
        const m = t.match(/^((?:[a-z0-9-]+\.)+([a-z]{2,24}))(:\d+)?(\/\S*)?$/i);
        if (m && (t.toLowerCase().startsWith("www.") || !fileEndings.includes(m[2].toLowerCase())))
            return "https://" + t;
        return "";
    }
    function urlResult(url) {
        return { kind: "url", title: "Open " + url.replace(/^https?:\/\//, ""), subtitle: "In your browser", icon: "link", value: url };
    }

    function hint(title, subtitle, icon) {
        return { kind: "hint", title: title, subtitle: subtitle, icon: icon };
    }

    // `settings` (optional): text -> the Settings rows it finds, best first.
    function results(query, settings) {
        countsVersion;
        switch (modeOf(query)) {
        case "emoji":
            return emojiResults(termOf(query));
        case "files":
            return fileResults(termOf(query));
        case "web":
            return webResults(termOf(query));
        case "translate":
            return translateResults(termOf(query));
        }
        const q = query.trim().toLowerCase();
        const out = [];

        if (q === "") {
            // Most opened first, then your favourites, then A to Z.
            const fav = id => {
                const i = Style.launcherFavorites.indexOf(id);
                return i < 0 ? 999 : i;
            };
            const sorted = apps.slice().sort((a, b) => (counts[b.id] ?? 0) - (counts[a.id] ?? 0)
                                                      || fav(a.id) - fav(b.id)
                                                      || a.name.localeCompare(b.name));
            return sorted.map(appResult);
        }

        const value = Calc.evaluate(q);
        if (value !== null)
            out.push({ kind: "calc", title: Calc.format(value), subtitle: q + "  ·  Enter copies it", icon: "calculate", value: Calc.format(value) });

        const scored = [];
        for (const a of apps) {
            const m = matchOf(a, q);
            if (m > 0)
                scored.push({ s: m + nudge(a), named: m >= 65, a: a });
        }
        if (settings) {
            const found = settings(q);
            for (let i = 0; i < found.length; i++)
                scored.push({ s: -i, r: found[i] });
        }
        // Apps whose name has what you typed come first (by how well it
        // matches, not counting how often you open them), then settings in
        // their own order, then apps found by their description or loosely.
        const group = x => x.r ? 1 : x.named ? 0 : 2;
        scored.sort((x, y) => group(x) - group(y) || y.s - x.s || (x.a?.name ?? "").localeCompare(y.a?.name ?? ""));
        for (const x of scored.slice(0, 40))
            out.push(x.a ? appResult(x.a) : x.r);

        if (Style.launcherWeb) {
            const url = urlOf(query);
            if (url !== "")
                out.push(urlResult(url));
            out.push(webResult(query.trim()));
        }
        return out;
    }

    function emojiResults(term) {
        if (!Emoji.loaded)
            return [hint("Loading emoji…", "", "mood")];
        const found = Emoji.search(term);
        return found.length > 0 ? found : [hint("No emoji called “" + term + "”", "Try a word like fire, heart, laugh", "mood")];
    }

    function fileResults(term) {
        const where = Style.fileSearchRoot;
        if (term === "")
            return [hint("Type part of a file or folder name", "Searching in " + where, "folder_open")];
        const found = FileSearch.results;
        if (found.length === 0)
            return [FileSearch.busy ? hint("Searching…", "In " + where, "hourglass_empty")
                                    : hint("Nothing called “" + term + "”", "In " + where + " (hidden folders too: start with a dot)", "search_off")];
        const home = FileSearch.home;
        return found.map(f => ({
            kind: "file",
            title: f.name,
            subtitle: (f.dir.startsWith(home) ? "~" + f.dir.slice(home.length) : f.dir) || "/",
            icon: fileIcon(f),
            value: f.path,
            isDir: f.isDir
        }));
    }

    function webResults(term) {
        if (term === "")
            return [hint("Type what to search " + engine + " for", "Enter opens your browser", "travel_explore")];
        const url = urlOf(term);
        return (url !== "" ? [urlResult(url)] : []).concat([webResult(term)]);
    }

    // ---- Translating: "tr hello" (services/Translator.qml) -----------------------
    // The text goes to Google, so nothing is sent until "tr ", 2 letters or
    // more, and a pause in typing (translateDelay); each new text cancels
    // the one asked before, and closing the launcher cancels it too.
    // "tr ja: hello" asks for Japanese (a language Translator knows by
    // name); otherwise the pair's rule picks the way (Style.translatePair).
    readonly property int translateDelay: 450
    // { text, target ("" = the pair's rule), state: "wait" | "busy" | "done"
    //   | "error", translation, from, to, error } of the last text typed;
    // null: nothing asked. While a new text waits, the last answer stays.
    property var translation: null
    property var translated: null       // the last answer: { text, target, translation, from, to }
    property string translateId: ""
    property int translateCount: 0

    // "ja: hello" → { target: "ja", text: "hello" }; "re: hello" is just text.
    function translateAsk(term) {
        const m = term.match(/^([A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?)\s*:\s*([\s\S]*)$/);
        if (m && Translator.languageName(m[1]) !== m[1].toUpperCase())
            return { target: m[1], text: m[2].trim() };
        return { target: "", text: term };
    }
    // Letters (and other signs of words: ideographs, kana…), no digits,
    // spaces or ASCII punctuation (QML's JavaScript has no \p{L}).
    function letters(text) {
        return text.replace(/[\s0-9!-\/:-@\[-`{-~]/g, "").length;
    }

    function translateLater(term) {
        const ask = translateAsk(term);
        if (letters(ask.text) < 2) {
            stopTranslating();
            return;
        }
        if (translation && translation.text === ask.text && translation.target === ask.target)
            return;
        cancelTranslation();
        translation = { text: ask.text, target: ask.target, state: "wait" };
        translateTimer.restart();
    }

    function cancelTranslation() {
        translateTimer.stop();
        if (translateId !== "")
            Translator.cancel(translateId);
        translateId = "";
    }

    function stopTranslating() {
        if (translation === null && translated === null && translateId === "")
            return;
        cancelTranslation();
        translation = null;
        translated = null;
    }

    Timer {
        id: translateTimer
        interval: root.translateDelay
        onTriggered: {
            const t = root.translation;
            if (!t)
                return;
            root.translateId = "launcher-" + (++root.translateCount);
            root.translation = Object.assign({}, t, { state: "busy" });
            if (!Translator.request(root.translateId, t.text, t.target || "auto")) {
                root.translateId = "";
                root.translation = Object.assign({}, t, { state: "error", error: "Nothing to translate" });
            }
        }
    }

    Connections {
        target: root.translation !== null ? Translator : null
        function onFinished(id, ok, translation, from, to, error) {
            if (id !== root.translateId)
                return;
            root.translateId = "";
            const t = root.translation;
            root.translation = Object.assign({}, t, { state: ok ? "done" : "error", translation: translation, from: from, to: to, error: error });
            if (ok)
                root.translated = { text: t.text, target: t.target, translation: translation, from: from, to: to };
        }
    }

    function translateResults(term) {
        const ask = translateAsk(term);
        const toName = ask.target !== "" ? Translator.languageName(ask.target) : "";
        if (letters(ask.text) < 2)
            return [hint(toName !== "" ? "Type what to translate to " + toName : "Type what to translate",
                         toName !== "" ? "Enter copies the translation" : "“tr ja: hello” picks the language", "translate")];
        const t = translation;
        const way = (from, to) => (from ? Translator.languageName(from) + " → " : "") + Translator.languageName(to);
        if (t && t.state === "done" && t.text === ask.text && t.target === ask.target)
            return [{ kind: "translate", title: t.translation, subtitle: way(t.from, t.to) + "  ·  Enter copies it", icon: "translate", value: t.translation }];
        if (t && t.state === "error" && t.text === ask.text && t.target === ask.target)
            return [hint("Couldn't translate", t.error || "No answer from Google", "translate")];
        // Waiting: the last answer stays (no flicker on every key), dimmed by "…".
        const last = translated;
        const target = ask.target || Translator.targetFor(ask.text);
        return [last ? { kind: "hint", title: last.translation, subtitle: "Translating…  ·  " + way(Translator.guess(ask.text), target), icon: "translate" }
                     : hint("Translating…", way(Translator.guess(ask.text), target), "hourglass_empty")];
    }

    // A themed icon for a file, by its kind (from the name's ending).
    function fileIcon(f) {
        if (f.isDir)
            return Quickshell.iconPath("folder", "inode-directory");
        const ext = (f.name.includes(".") ? f.name.split(".").pop() : "").toLowerCase();
        const kinds = {
            "image-x-generic": ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "avif", "heic", "ico", "tiff"],
            "video-x-generic": ["mp4", "mkv", "webm", "mov", "avi", "m4v"],
            "audio-x-generic": ["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac"],
            "application-pdf": ["pdf"],
            "package-x-generic": ["zip", "tar", "gz", "xz", "zst", "7z", "rar", "bz2", "deb", "rpm"],
            "x-office-document": ["doc", "docx", "odt", "rtf"],
            "x-office-spreadsheet": ["xls", "xlsx", "ods", "csv"],
            "x-office-presentation": ["ppt", "pptx", "odp"],
            "text-html": ["html", "htm"],
            "text-x-script": ["sh", "fish", "zsh", "bash", "py", "js", "ts", "qml", "c", "h", "cpp", "rs", "go", "java", "lua", "rb"],
            "text-x-generic": ["txt", "md", "conf", "ini", "toml", "json", "yaml", "yml", "log", "xml"]
        };
        for (const icon in kinds)
            if (kinds[icon].includes(ext))
                return Quickshell.iconPath(icon, "text-x-generic");
        return Quickshell.iconPath("text-x-generic", "unknown");
    }

    function appResult(a) {
        return { kind: "app", title: a.name, subtitle: a.genericName || a.comment || "", icon: iconFor(a), entry: a };
    }

    // Name matches beat description matches; often-opened apps get a nudge.
    function score(a, q) {
        const m = matchOf(a, q);
        return m > 0 ? m + nudge(a) : 0;
    }
    function nudge(a) {
        return Math.min(25, (counts[a.id] ?? 0) * 3);
    }

    // How well the app fits what's typed: 120 its whole name, 100 its
    // start, 85 a word's start, 65 inside the name; 50 / 35 its description,
    // keywords, id or program; 16-25 its letters in order; 0 not at all.
    function matchOf(a, q) {
        const name = a.name.toLowerCase();
        let s = 0;
        if (name === q)
            s = 120;
        else if (name.startsWith(q))
            s = 100;
        else if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            s = 85;
        else if (name.includes(q))
            s = 65;
        else {
            const exec = (a.command?.[0] ?? "").split("/").pop();
            const other = [a.genericName, a.comment, (a.keywords ?? []).join(" "), a.id, exec].join(" ").toLowerCase();
            if (other.split(/[\s;,\-_.]+/).some(w => w.startsWith(q)))
                s = 50;
            else if (other.includes(q))
                s = 35;
            else {
                const f = fuzzy(name, q);
                if (f > 0)
                    s = 15 + f;
            }
        }
        if (s === 0)
            return 0;
        // My shell's own settings (mine-settings.desktop) before the other
        // "Settings" apps; by its name only: for "dock" or "wallpaper" (its
        // keywords) the Settings rows themselves go first.
        if (a.id === "mine-settings" && s >= 65)
            s += 40;
        return s;
    }

    // Letters in order (f-x for firefox): 1-10, tighter is better; 0 if not.
    function fuzzy(text, q) {
        let at = 0, first = -1, last = -1;
        for (const ch of q) {
            at = text.indexOf(ch, at);
            if (at < 0)
                return 0;
            if (first < 0)
                first = at;
            last = at;
            at++;
        }
        return Math.max(1, 10 - (last - first + 1 - q.length));
    }

    function iconFor(a) {
        const icon = a.icon ?? "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }

    // `inFolder` (Ctrl+Enter): a file's folder instead of the file.
    // False when there was nothing to do (a hint row): the launcher stays.
    function run(r, inFolder) {
        if (!r || r.kind === "hint")
            return false;
        if (r.kind === "app")
            launch(r.entry);
        else if (r.kind === "setting")
            SettingsState.reveal(r.value.section, r.value.ref);
        else if (r.kind === "calc" || r.kind === "translate")
            detached(["wl-copy", "--", r.value]);      // "--": a result can be "-5"
        else if (r.kind === "web")
            detached(["xdg-open", webUrl(r.value)]);
        else if (r.kind === "url")
            detached(["xdg-open", r.value]);
        else if (r.kind === "emoji")
            Emoji.pick(r.value);
        else if (r.kind === "file")
            detached(["xdg-open", inFolder ? r.value.slice(0, r.value.lastIndexOf("/")) || "/" : r.value]);
        return true;
    }

    function launch(a) {
        counts[a.id] = (counts[a.id] ?? 0) + 1;
        countsVersion++;
        saveTimer.restart();
        if (a.runInTerminal)
            detached(["xdg-terminal-exec"].concat(a.command));
        else if (dryRun)
            console.log("launcher (dry run): execute", a.id);
        else
            a.execute();
    }

    function detached(cmd) {
        if (dryRun)
            console.log("launcher (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // ---- The app grid (launcher/AppGrid.qml) ---------------------------------------
    // Every app A to Z, in a few groups by its desktop entry's Categories:
    // the first group in `groupPick` that has one of them (a game that's
    // also a network app is a game); none of them: Other. Groups with no
    // apps aren't shown. Only worked out once the grid is first wanted
    // (gridWanted), then kept up to date with the app list.
    readonly property var gridGroups: [
        { id: "all", label: "All", icon: "apps" },
        { id: "internet", label: "Internet", icon: "language" },
        { id: "media", label: "Media", icon: "play_circle" },
        { id: "office", label: "Office", icon: "description" },
        { id: "development", label: "Development", icon: "code" },
        { id: "games", label: "Games", icon: "sports_esports" },
        { id: "system", label: "System", icon: "tune" },
        { id: "utilities", label: "Utilities", icon: "handyman" },
        { id: "other", label: "Other", icon: "category" }
    ]
    readonly property var groupPick: [
        ["games", ["Game"]],
        ["development", ["Development", "IDE", "Debugger", "RevisionControl", "WebDevelopment", "GUIDesigner"]],
        ["system", ["Settings", "DesktopSettings", "HardwareSettings", "PackageManager"]],
        ["internet", ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging", "IRCClient", "VideoConference",
                      "Feed", "News", "FileTransfer", "P2P", "RemoteAccess"]],
        ["media", ["AudioVideo", "Audio", "Video", "Graphics", "Photography", "Music", "Player", "Recorder", "TV",
                   "2DGraphics", "3DGraphics", "RasterGraphics", "VectorGraphics"]],
        ["office", ["Office", "Education", "Science", "Math", "Spreadsheet", "WordProcessor", "Presentation",
                    "Calendar", "ContactManager", "Finance", "Dictionary", "Literature"]],
        ["utilities", ["FileManager"]],
        ["system", ["System", "TerminalEmulator", "Monitor", "Security", "Emulator"]],
        ["utilities", ["Utility", "Accessibility", "TextEditor", "Archiving", "Compression", "Calculator", "Clock",
                       "FileTools", "Core"]]
    ]
    function groupOf(entry) {
        const cats = entry?.categories ?? [];
        for (const [group, names] of groupPick) {
            for (let i = 0; i < cats.length; i++) {
                if (names.includes(cats[i]))
                    return group;
            }
        }
        return "other";
    }

    property bool gridWanted: false
    // [{ kind: "app", title, subtitle, icon, entry, group }], A to Z.
    readonly property var gridApps: gridWanted
        ? apps.map(a => Object.assign(appResult(a), { group: groupOf(a) })).sort((x, y) => x.title.localeCompare(y.title))
        : []
    readonly property var gridGroupsShown: gridGroups.filter(g => g.id === "all" || gridApps.some(a => a.group === g.id))
    function gridOf(group) {
        return group === "all" ? gridApps : gridApps.filter(a => a.group === group);
    }

    // ---- An app's own actions ("New Window", "New Private Window", …) -----------
    // From its desktop entry ([Desktop Action …]); the dock's right-click
    // menu, the launcher's actions menu (→ on a result) and the grid's long
    // press list them. [{ id, name, icon (a Material Symbols name), action }]
    function actionsOf(entry) {
        const list = entry?.actions ?? [];
        const out = [];
        for (let i = 0; i < list.length && out.length < 8; i++) {
            const a = list[i];
            if (a && (a.name ?? "") !== "")
                out.push({ id: a.id, name: a.name, icon: /private|incognito/i.test(a.name + " " + a.id) ? "visibility_off" : "open_in_new", action: a });
        }
        return out;
    }

    // The app's own "new window" action ("New Window", new-window), or
    // null: a "New window" row runs it instead of starting the app again
    // (some apps only bring their window forward then), and it isn't
    // listed a second time.
    function isNewWindow(a) {
        return (a?.id ?? "").toLowerCase().replace(/[^a-z]/g, "") === "newwindow"
            || (a?.name ?? "").toLowerCase().replace(/[^a-z]/g, "") === "newwindow";
    }
    function newWindowOf(entry) {
        return actionsOf(entry).find(a => isNewWindow(a))?.action ?? null;
    }

    // Like launch(), for one of its actions (a terminal app's in the terminal).
    function launchAction(entry, action) {
        if (!entry || !action)
            return;
        counts[entry.id] = (counts[entry.id] ?? 0) + 1;
        countsVersion++;
        saveTimer.restart();
        if (entry.runInTerminal)
            detached(["xdg-terminal-exec"].concat(action.command));
        else if (dryRun)
            console.log("launcher (dry run): execute action", entry.id, action.id);
        else
            action.execute();
    }

    // ---- Saving how often apps are opened -------------------------------------
    Timer {
        id: saveTimer
        interval: 500
        onTriggered: store.setText(JSON.stringify({ counts: root.counts }, null, 1))
    }

    FileView {
        id: store
        path: root.statePath
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                root.counts = JSON.parse(text()).counts ?? {};
                root.countsVersion++;
            } catch (e) {
                console.warn("launcher: can't read", root.statePath);
            }
        }
    }
}
