pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "termcolors.js" as TermColors

// The wallpaper, and the colors that follow it.
//
// - `current` is drawn by wallpaper/WallpaperWindow.qml and remembered in
//   ~/.local/state/mine-shell/wallpaper.json.
// - Each change asks matugen for the Material colors of the new picture
//   (only as JSON on stdout: matugen itself never writes a file) and writes:
//     ~/.local/state/mine-shell/colors.json   read live by common/Colors.qml
//     ~/.config/quickshell/lock/Theme.qml      the lock screen
//     ~/.config/mango/noctalia-colors.conf     window borders (then mango reloads)
//     ~/.config/foot/themes/noctalia           foot's colors (new foot windows)
//     ~/.local/state/mine-shell/starship.toml  the prompt, in the same colors
//       (fish uses it while it exists: ~/.config/fish/conf.d/mine-starship.fish;
//       starship reads it at every prompt, so open terminals follow too)
//     ~/.local/state/mine-shell/gtk/gtk{3,4}.css  GTK apps' colors, copied to
//       ~/.config/gtk-{3,4}.0/gtk.css in the mango session only
//       (Style.themeApps; see ../scripts/gtk-colors.sh)
//   from the templates in ../matugen/, light or dark as Theme says.
// - Style.wallpaperDaily "bing": Bing's picture of the day, downloaded to
//   <wallpaperDir>/Daily (the last 14 kept) and set once each new day.
// - The picker (Super+Y) lists ~/Pictures/Wallpapers with thumbnails cached
//   in ~/.cache/mine-shell/thumbs.
//
// MINE_WALLPAPER_STATE, MINE_COLORS_JSON, MINE_LOCK_THEME, MINE_MANGO_COLORS,
// MINE_FOOT_COLORS, MINE_STARSHIP, MINE_THUMB_DIR, MINE_WALLPAPER_DRYRUN=1 (don't reload
// mango), MINE_GTK_STATE, MINE_GTK_CONFIG (instead of ~/.config),
// MINE_DAILY_URL, MINE_DAILY_HOST, MINE_DAILY_DIR and MINE_DAILY_STATE are
// for testing.
Singleton {
    id: root

    property string current: ""
    // Where the next wallpaper spreads from, as a fraction of the screen.
    // The picker sets it to the thumbnail you clicked.
    property point origin: Qt.point(0.5, 0)

    property var list: []           // every picture in Style.wallpaperDir
    property var thumbs: ({})       // picture -> thumbnail file url
    property int thumbsVersion: 0

    property bool pickerOpen: false
    property bool pickerMapped: false

    readonly property string home: Quickshell.env("HOME")
    readonly property bool dryRun: Quickshell.env("MINE_WALLPAPER_DRYRUN") === "1"
    readonly property string statePath: Quickshell.env("MINE_WALLPAPER_STATE")
        || (home + "/.local/state/mine-shell/wallpaper.json")
    readonly property string lockThemePath: Quickshell.env("MINE_LOCK_THEME")
        || (home + "/.config/quickshell/lock/Theme.qml")
    readonly property string mangoColorsPath: Quickshell.env("MINE_MANGO_COLORS")
        || (home + "/.config/mango/noctalia-colors.conf")
    readonly property string footColorsPath: Quickshell.env("MINE_FOOT_COLORS")
        || (home + "/.config/foot/themes/noctalia")
    readonly property string starshipPath: Quickshell.env("MINE_STARSHIP")
        || (home + "/.local/state/mine-shell/starship.toml")
    readonly property string thumbDir: Quickshell.env("MINE_THUMB_DIR")
        || (home + "/.cache/mine-shell/thumbs")
    readonly property string gtkStateDir: Quickshell.env("MINE_GTK_STATE")
        || (home + "/.local/state/mine-shell/gtk")
    readonly property string gtkConfigHome: Quickshell.env("MINE_GTK_CONFIG")
        || (home + "/.config")
    // GTK's files are shared with GNOME and Hyprland: only written here.
    readonly property bool inMango: (Quickshell.env("XDG_CURRENT_DESKTOP") ?? "").toLowerCase().split(":").includes("mango")

    // Light or dark (services/Theme.qml); a change recolors everything.
    readonly property bool dark: Theme.dark
    // One more each time the templates (../matugen/) change, so the files
    // are made again at the next start instead of at the next wallpaper.
    readonly property int colorsVersion: 2
    onDarkChanged: if (current !== "") generate()

    // ---- What the picker, IPC and keys call ---------------------------------------

    function set(path, from) {
        if (!path || path === current)
            return;
        origin = from ?? Qt.point(0.5, 0);
        current = path;
        stateFile.setText(JSON.stringify({ path: path }, null, 1));
        generate();
    }

    function next(from) {
        whenListed(() => {
            const i = list.indexOf(current);
            set(list[(i + 1) % list.length], from);
        });
    }

    function random(from) {
        whenListed(() => {
            const others = list.filter(p => p !== current);
            if (others.length > 0)
                set(others[Math.floor(Math.random() * others.length)], from);
        });
    }

    // ---- Slideshow ---------------------------------------------------------------
    // Every Style.wallpaperSlideshow minutes (0 = off) the next picture,
    // colors and all: a random one, or the next in the folder
    // (Style.wallpaperSlideshowOrder). It spreads from a random spot along
    // the top, and waits while the screen is dimmed or off.
    Timer {
        id: slideshow
        interval: Math.max(1, Style.wallpaperSlideshow) * 60000
        repeat: true
        running: Style.wallpaperSlideshow > 0 && root.current !== "" && !Idle.dimmed && !Idle.screenOff
        onTriggered: {
            const from = Qt.point(0.15 + Math.random() * 0.7, 0);
            if (Style.wallpaperSlideshowOrder === "next")
                root.next(from);
            else
                root.random(from);
        }
    }

    function setPicker(open) {
        if (open) {
            pickerUnmap.stop();
            pickerMapped = true;
            scan();
        } else {
            pickerUnmap.restart();
        }
        pickerOpen = open;
    }

    // The picker is back in the middle island: its window can go.
    function pickerSettled() {
        if (pickerOpen || !pickerMapped)
            return;
        pickerUnmap.stop();
        // The window goes a moment later, not in the very frame the island
        // starts fading back in: letting go of a window stalls the shell
        // for ~50 ms, which made that fade stutter.
        pickerRelease.restart();
    }
    Timer {
        id: pickerRelease
        interval: Motion.contentIn + 80
        onTriggered: if (!root.pickerOpen) root.pickerMapped = false
    }

    function togglePicker() {
        setPicker(!pickerOpen);
    }

    // Picture name for the picker: "Nature-Space · sky abyssal wave".
    function label(path) {
        const day = daily.titles?.[path];
        if (day)
            return "Picture of the day  ·  " + day.title;
        const rel = path.startsWith(Style.wallpaperDir + "/") ? path.substring(Style.wallpaperDir.length + 1) : path;
        const parts = rel.split("/");
        const name = parts.pop().replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ");
        return parts.length > 0 ? parts.join(" / ") + "  ·  " + name : name;
    }

    // ---- Finding the pictures and their thumbnails --------------------------------

    property var afterScan: []

    function whenListed(fn) {
        if (list.length > 0)
            fn();
        else {
            afterScan.push(fn);
            scan();
        }
    }

    function scan() {
        if (!finder.running)
            finder.running = true;
    }

    Process {
        id: finder
        command: ["find", Style.wallpaperDir, "-type", "f", "(",
                  "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o",
                  "-iname", "*.png", "-o", "-iname", "*.webp", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Only when it changed: a new list rebuilds the picker's whole
                // grid, which would happen right while it opens.
                const found = text.split("\n").filter(l => l !== "").sort((a, b) => a.localeCompare(b));
                if (found.join("\n") !== root.list.join("\n"))
                    root.list = found;
                const waiting = root.afterScan;
                root.afterScan = [];
                for (const fn of waiting)
                    fn();
                if (root.pickerOpen && !thumbnailer.running) {
                    thumbnailer.command = ["sh", Quickshell.shellDir + "/scripts/wallpaper-thumbs.sh", root.thumbDir].concat(root.list);
                    thumbnailer.running = true;
                }
            }
        }
    }

    Process {
        id: thumbnailer
        stdout: SplitParser {
            onRead: line => {
                const [picture, thumb] = line.split("\t");
                // Known already (every opening lists them all again): no
                // change, so the picker's cells aren't asked to look again
                // one line at a time while it opens.
                if (!thumb || root.thumbs[picture] === "file://" + thumb)
                    return;
                root.thumbs[picture] = "file://" + thumb;
                root.thumbsVersion++;
            }
        }
    }

    // The window goes once the picker reports it's back in the island
    // (pickerSettled). This is only a safety net in case it never does.
    Timer {
        id: pickerUnmap
        interval: Motion.morphOut + 1500
        onTriggered: root.pickerMapped = false
    }

    // ---- Colors ---------------------------------------------------------------------

    // Our names (textOn* for on_*) -> matugen's.
    readonly property var roles: ({
        primary: "primary", textOnPrimary: "on_primary",
        primaryContainer: "primary_container", textOnPrimaryContainer: "on_primary_container",
        secondary: "secondary", textOnSecondary: "on_secondary",
        secondaryContainer: "secondary_container", textOnSecondaryContainer: "on_secondary_container",
        tertiary: "tertiary", textOnTertiary: "on_tertiary",
        tertiaryContainer: "tertiary_container", textOnTertiaryContainer: "on_tertiary_container",
        error: "error", textOnError: "on_error",
        errorContainer: "error_container", textOnErrorContainer: "on_error_container",
        surface: "surface", textOnSurface: "on_surface",
        surfaceVariant: "surface_variant", textOnSurfaceVariant: "on_surface_variant",
        surfaceContainerLowest: "surface_container_lowest", surfaceContainerLow: "surface_container_low",
        surfaceContainer: "surface_container", surfaceContainerHigh: "surface_container_high",
        surfaceContainerHighest: "surface_container_highest",
        outline: "outline", outlineVariant: "outline_variant",
        shadow: "shadow", scrim: "scrim",
        inverseSurface: "inverse_surface", inverseOnSurface: "inverse_on_surface"
    })

    // One matugen at a time; a change during a run is picked up right after.
    function generate() {
        if (matugen.running) {
            matugen.again = true;
            return;
        }
        matugen.forPath = current;
        matugen.command = ["matugen", "image", current, "--dry-run", "-j", "hex",
                           "-m", root.dark ? "dark" : "light", "-t", Style.wallpaperScheme,
                           "--source-color-index", "0",
                           "-c", Quickshell.shellDir + "/matugen/config.toml"];
        matugen.running = true;
    }

    Process {
        id: matugen
        property string forPath: ""
        property bool again: false
        stdout: StdioCollector {
            onStreamFinished: root.apply(matugen.forPath, text)
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("matugen:", text.trim())
        }
        onExited: {
            if (again) {
                again = false;
                root.generate();
            }
        }
    }

    function apply(path, json) {
        if (path !== current)
            return;      // an older run finished after a newer change
        let colors;
        try {
            colors = JSON.parse(json).colors;
        } catch (e) {
            console.warn("wallpaper: matugen gave no colors for", path);
            return;
        }
        // variant: "default" (the mode asked for), "light" or "dark".
        const pick = (key, variant) => colors[key]?.[variant ?? "default"]?.color
            ?? colors[key]?.default?.color ?? "#000000";

        // The terminal's red, green, … (termcolors.js), usable in the
        // templates like any role: {{colors.term_red.default.hex}}.
        const term = TermColors.palette(key => pick(key), root.dark);
        for (const name in term)
            colors[name] = { default: { color: term[name] } };

        const ours = { wallpaper: path, scheme: Style.wallpaperScheme, mode: root.dark ? "dark" : "light",
                       version: root.colorsVersion };
        for (const name in roles)
            ours[name] = pick(roles[name]);
        colorsFile.setText(JSON.stringify(ours, null, 1));

        // matugen's template words: {{ image }} and
        // {{colors.<name>.<default|light|dark>.<hex|hex_stripped|red|green|blue>}}.
        // {{ image }} becomes a quoted, escaped string (JSON is valid QML),
        // so a file name with " or \ can't end the string early. A function,
        // not a string: replace() would read "$'" or "$&" in the name.
        const render = template => template
            .replace(/\{\{\s*image\s*\}\}/g, () => JSON.stringify(path))
            .replace(/\{\{\s*colors\.(\w+)\.(default|light|dark)\.(hex_stripped|hex|red|green|blue)\s*\}\}/g,
                     (m, key, variant, form) => {
                         const hex = pick(key, variant);
                         if (form === "hex")
                             return hex;
                         if (form === "hex_stripped")
                             return hex.substring(1);
                         const at = { red: 1, green: 3, blue: 5 }[form];
                         return String(parseInt(hex.substring(at, at + 2), 16));
                     });
        lockThemeFile.setText(render(lockTemplate.text()));
        mangoColorsFile.setText(render(mangoTemplate.text()));
        // foot reads it when a new window opens (same file Noctalia wrote,
        // so foot.ini stays as it is).
        footColorsFile.setText(render(footTemplate.text()));
        starshipFile.setText(render(starshipTemplate.text()));
        // GTK apps: written first, put in place by installGtk().
        gtk3File.setText(render(gtk3Template.text()));
        gtk4File.setText(render(gtk4Template.text()));
        installGtk();

        if (dryRun)
            console.log("wallpaper (dry run): would run mmsg dispatch reload_config");
        else
            Quickshell.execDetached(["mmsg", "dispatch", "reload_config"]);
        greeterSync.restart();
    }

    // The login screen (greetd + greeter.qml) shows the same wallpaper,
    // colors and picture: scripts/greeter-sync.sh copies them where it can
    // read them, once colors.json is on disk. Nothing happens until the
    // login screen is installed.
    Timer {
        id: greeterSync
        interval: 1500
        onTriggered: {
            if (root.dryRun)
                console.log("wallpaper (dry run): would run greeter-sync.sh");
            else
                Quickshell.execDetached(["sh", Quickshell.shellDir + "/scripts/greeter-sync.sh"]);
        }
    }

    FileView {
        id: colorsFile
        path: Colors.path
        atomicWrites: true
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: lockThemeFile
        path: root.lockThemePath
        atomicWrites: true
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: mangoColorsFile
        path: root.mangoColorsPath
        atomicWrites: true
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: footColorsFile
        path: root.footColorsPath
        atomicWrites: true
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: starshipFile
        path: root.starshipPath
        atomicWrites: true
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: gtk3File
        path: root.gtkStateDir + "/gtk3.css"
        atomicWrites: true
        blockWrites: true           // on disk before gtk-colors.sh copies it
        printErrors: false
    }
    FileView {
        id: gtk4File
        path: root.gtkStateDir + "/gtk4.css"
        atomicWrites: true
        blockWrites: true
        printErrors: false
    }
    FileView {
        id: gtk3Template
        path: Quickshell.shellDir + "/matugen/gtk-3.0.css.in"
        blockLoading: true
    }
    FileView {
        id: gtk4Template
        path: Quickshell.shellDir + "/matugen/gtk-4.0.css.in"
        blockLoading: true
    }
    FileView {
        id: footTemplate
        path: Quickshell.shellDir + "/matugen/foot-colors.ini.in"
        blockLoading: true
    }
    FileView {
        id: starshipTemplate
        path: Quickshell.shellDir + "/matugen/starship.toml.in"
        blockLoading: true
    }
    FileView {
        id: lockTemplate
        path: Quickshell.shellDir + "/matugen/lock-theme.qml.in"
        blockLoading: true
    }
    FileView {
        id: mangoTemplate
        path: Quickshell.shellDir + "/matugen/mango-colors.conf.in"
        blockLoading: true
    }

    // ---- Start-up ---------------------------------------------------------------------

    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        printErrors: false

        onLoaded: {
            let saved = "";
            try {
                saved = JSON.parse(text()).path ?? "";
            } catch (e) {}
            root.start(saved);
        }
        onLoadFailed: root.start("")
    }

    // Nothing saved yet (first start after Noctalia): take Noctalia's wallpaper.
    Process {
        id: askNoctalia
        command: ["noctalia", "msg", "wallpaper-get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim().split("\n")[0] ?? "";
                if (path.startsWith("/"))
                    root.set(path);
                else
                    root.whenListed(() => root.set(root.list[0]));
            }
        }
    }

    function start(saved) {
        if (saved === "") {
            askNoctalia.running = true;
            return;
        }
        current = saved;
        // Colors missing or made for another picture (or light/dark, or by
        // older templates): make them now; otherwise make sure GTK has them (Hyprland may have put
        // its own there since).
        colorsCheck.restart();
    }

    // Colors.qml reads its file asynchronously; give it a moment first.
    Timer {
        id: colorsCheck
        interval: 600
        onTriggered: {
            if (Colors.wallpaper !== root.current || (Colors.c.mode ?? "dark") !== (root.dark ? "dark" : "light")
                    || (Colors.c.version ?? 0) !== root.colorsVersion)
                root.generate();
            else
                root.installGtk();
        }
    }

    // From the Settings window: another color style recolors from the same
    // picture; another folder lists its pictures.
    Connections {
        target: Style
        function onWallpaperSchemeChanged() {
            if (root.current !== "")
                root.generate();
        }
        function onWallpaperDirChanged() {
            root.list = [];
            root.scan();
        }
        function onThemeAppsChanged() {
            if (Style.themeApps)
                root.installGtk();
            else if (root.inMango)
                Quickshell.execDetached(["sh", Quickshell.shellDir + "/scripts/gtk-colors.sh", "remove", root.gtkConfigHome]);
        }
    }

    // ---- GTK apps ---------------------------------------------------------------------
    // The colors written by apply() go to ~/.config/gtk-{3,4}.0/gtk.css, in the
    // mango session only. GTK reads them when an app starts (open windows keep
    // their colors until restarted). Missing (first run): made now.
    function installGtk() {
        if (!Style.themeApps || !inMango)
            return;
        if (!gtkInstaller.running)
            gtkInstaller.running = true;
        else
            gtkInstaller.again = true;
    }
    Process {
        id: gtkInstaller
        property bool again: false
        command: ["sh", Quickshell.shellDir + "/scripts/gtk-colors.sh", "install", root.gtkStateDir, root.gtkConfigHome]
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn(text.trim())
        }
        onExited: code => {
            if (code === 3 && root.current !== "")
                root.generate();
            else if (again) {
                again = false;
                running = true;
            }
        }
    }

    // ---- Picture of the day --------------------------------------------------------------
    // Style.wallpaperDaily "bing": asks Bing at start and every 3 hours; a new
    // day's picture is downloaded to <wallpaperDir>/Daily and set (once: pick
    // another wallpaper and it stays until the next day's). The last 14 are
    // kept. Offline: tried again later, one line in the log.
    readonly property string dailyUrl: Quickshell.env("MINE_DAILY_URL")
        || "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US"
    readonly property string dailyHost: Quickshell.env("MINE_DAILY_HOST") || "https://www.bing.com"
    readonly property string dailyDir: Quickshell.env("MINE_DAILY_DIR") || (Style.wallpaperDir + "/Daily")
    readonly property string dailyStatePath: Quickshell.env("MINE_DAILY_STATE")
        || (home + "/.local/state/mine-shell/daily.json")
    // { last: "20261015" (the day last set), titles: { "<file>": { title, copyright } } }
    property var daily: ({})
    property bool dailyLoaded: false
    property bool dailyQuiet: false         // already said it's offline

    FileView {
        id: dailyState
        path: root.dailyStatePath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                root.daily = JSON.parse(text()) ?? {};
            } catch (e) {
                root.daily = {};
            }
            root.dailyLoaded = true;
        }
        onLoadFailed: root.dailyLoaded = true
    }
    function saveDaily() {
        dailyState.setText(JSON.stringify(daily, null, 1));
    }

    Timer {
        interval: 3 * 3600 * 1000
        repeat: true
        triggeredOnStart: true
        running: Style.wallpaperDaily === "bing" && root.dailyLoaded
        onTriggered: if (!dailyAsk.running && !dailyGet.running) dailyAsk.running = true
    }
    Process {
        id: dailyAsk
        command: ["curl", "-fsS", "--max-time", "20", root.dailyUrl]
        stdout: StdioCollector {
            onStreamFinished: root.gotDaily(text)
        }
        onExited: code => {
            if (code !== 0 && !root.dailyQuiet) {
                root.dailyQuiet = true;
                console.log("wallpaper: no picture of the day (offline?), trying again later");
            }
        }
    }
    function gotDaily(text) {
        let img;
        try {
            img = JSON.parse(text).images[0];
        } catch (e) {
            return;
        }
        // The day becomes part of a file name and urlbase the end of the
        // download's address: only "20261015" and "/th?id=..." are taken.
        if (!/^\d{8}$/.test(img?.startdate ?? "") || !/^\/\S*$/.test(img?.urlbase ?? ""))
            return;
        dailyQuiet = false;
        const name = (img.urlbase.match(/OHR\.([^_.]+)/)?.[1] ?? "bing").replace(/[^\w-]/g, "");
        const file = dailyDir + "/" + img.startdate + "-" + name + ".jpg";
        // The newest 20 (file names start with the day).
        const titles = {};
        const old = daily.titles ?? {};
        for (const f of Object.keys(old).sort().reverse().slice(0, 19))
            titles[f] = old[f];
        titles[file] = { title: img.title ?? name, copyright: img.copyright ?? "" };
        daily = Object.assign({}, daily, { titles: titles });
        saveDaily();
        if (daily.last === img.startdate)
            return;                         // set already today
        dailyGet.day = img.startdate;
        dailyGet.file = file;
        dailyGet.command = ["sh", "-c",
            'mkdir -p "$1" && { [ -s "$2" ] || { curl -fsS --max-time 120 -o "$2.part" "$3" && mv -f "$2.part" "$2"; }; } '
            + '&& ls -1t "$1"/*.jpg | tail -n +15 | while IFS= read -r f; do rm -f -- "$f"; done',
            "sh", dailyDir, file, dailyHost + img.urlbase + "_UHD.jpg"];
        dailyGet.running = true;
    }
    Process {
        id: dailyGet
        property string day: ""
        property string file: ""
        onExited: code => {
            if (code !== 0) {
                console.log("wallpaper: couldn't download the picture of the day");
                return;
            }
            root.daily = Object.assign({}, root.daily, { last: day });
            root.saveDaily();
            root.list = [];
            root.set(file);
        }
    }

    Component.onCompleted: {
        const dir = statePath.substring(0, statePath.lastIndexOf("/"));
        Quickshell.execDetached(["mkdir", "-p", dir]);
        greeterSync.restart();      // a new picture (~/.face) since last time
    }
}
