pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.services

// What the Settings window shows: sections, each a list of rows. A row
// either changes a Style.qml knob (`name`) through Settings, or does
// something (`kind: "action"`, ...). To show a new knob, add a row:
//   { name: "dockIconSize", kind: "number", label: "Icon size",
//     desc: "...", from: 28, to: 64, step: 2, format: root.px }
// Kinds: number (slider), bool (switch), choice (segmented: `choices`),
// text (a one-line field; `commit(text)` to handle it yourself, `status()`
// to say something under the label), action (a button: `button`, `run`,
// `confirm` = press twice), info (`text()`), dnd (Silent), wallpaper
// (current wallpaper with buttons), baritems (the bar items editor, whole
// width: an island's `key`, or none for what isn't on the bar).
// A bool row can switch something else than one knob: `get()` and `flip()`.
// A section has `rows`, or `groups: [{ title, rows }]` for titled groups.
Singleton {
    id: root

    function percent(v) {
        return Math.round(v * 100) + "%";
    }
    function px(v) {
        return Math.round(v) + " px";
    }
    function count(v) {
        return String(Math.round(v));
    }
    function times(v) {
        return v.toFixed(2).replace(/0+$/, "").replace(/\.$/, "") + "×";
    }
    function secondsOf(v) {
        return v.toFixed(1).replace(/\.0$/, "") + " s";
    }
    function halfPx(v) {
        return (Math.round(v * 2) / 2) + " px";
    }
    function ms(v) {
        return v < 1000 ? Math.round(v) + " ms" : (v / 1000).toFixed(1).replace(/\.0$/, "") + " s";
    }
    // 0 = never; seconds, minutes or hours otherwise.
    function after(v) {
        if (v <= 0)
            return "Never";
        if (v < 60)
            return Math.round(v) + " s";
        if (v < 3600)
            return Math.round(v / 60) + " min";
        return (v / 3600).toFixed(1).replace(/\.0$/, "") + " h";
    }

    // A color typed as #RRGGBB, #AARRGGBB or a name ("black"); empty = default.
    function setColor(name, text) {
        const t = text.trim();
        if (t === "")
            Settings.reset(name);
        else if (/^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(t) || /^[a-z]+$/.test(t))
            Settings.set(name, t);
    }
    // A list typed with commas: "foot, zen" -> ["foot", "zen"].
    function setList(name, text) {
        const items = text.split(",").map(t => t.trim()).filter(t => t !== "");
        if (items.length === 0)
            Settings.reset(name);
        else
            Settings.set(name, items);
    }
    // A switch for one desktop widget: in or out of Style.desktopWidgets
    // (a new one goes at the end, the others keep their order).
    function widgetRow(id, label, desc) {
        return {
            kind: "bool", label: label, desc: desc, resets: [],
            get: () => Style.desktopWidgets.includes(id),
            flip: () => {
                const list = Style.desktopWidgets;
                Settings.set("desktopWidgets", list.includes(id) ? list.filter(n => n !== id) : list.concat([id]));
            }
        };
    }

    // "0.3.2", for About.
    property string quickshell: ""
    Process {
        running: true
        command: ["qs", "--version"]
        stdout: StdioCollector {
            onStreamFinished: root.quickshell = text.split("(")[0].replace("Quickshell", "").trim()
        }
    }

    readonly property var list: [
        {
            id: "appearance", title: "Appearance", icon: "palette",
            blurb: "Glass, text and the screen's corners, everywhere in the shell.",
            groups: [
                { title: "Glass", rows: [
                    { name: "islandOpacity", kind: "number", label: "Islands", desc: "How tinted the three islands are (mango blurs what's behind)", from: 0.2, to: 0.95, step: 0.05, format: root.percent },
                    { name: "islandSheen", kind: "number", label: "Shine", desc: "Soft light on the top half of the glass", from: 0, to: 0.2, step: 0.01, format: root.percent },
                    { name: "islandBorderWidth", kind: "number", label: "Edge", desc: "The thin light line around the glass", from: 0, to: 2, step: 0.5, format: root.halfPx },
                    { name: "islandBorder", kind: "text", label: "Edge color", desc: "#AARRGGBB (alpha first) or #RRGGBB", placeholder: "#1fffffff", commit: t => root.setColor("islandBorder", t) },
                    { name: "glassStyle", kind: "choice", label: "Glass style", desc: "Liquid: light catches the glass edge, a glow inside the top, a shade inside the bottom",
                      choices: [{ value: "liquid", label: "Liquid" }, { value: "flat", label: "Flat" }] },
                    { name: "shapeStyle", kind: "choice", label: "Shapes", desc: "Behind icons: Material's cookies, clovers and bursts, or plain circles",
                      choices: [{ value: "expressive", label: "Expressive" }, { value: "simple", label: "Circles" }] },
                    { name: "tileStyle", kind: "choice", label: "Control center tiles", desc: "An on tile fills with the accent, or stays calm with only its icon's circle in the accent",
                      choices: [{ value: "filled", label: "Filled" }, { value: "calm", label: "Calm" }] },
                    { name: "glassRim", kind: "number", label: "Rim light", desc: "The edge facing the light", from: 0, to: 0.8, step: 0.02, format: root.percent },
                    { name: "glassRimBack", kind: "number", label: "Far glint", desc: "The edge away from the light", from: 0, to: 0.5, step: 0.02, format: root.percent },
                    { name: "glassGlow", kind: "number", label: "Inner glow", desc: "Light just inside the top edge", from: 0, to: 0.25, step: 0.01, format: root.percent },
                    { name: "glassShade", kind: "number", label: "Inner shade", desc: "Shade just inside the bottom edge", from: 0, to: 0.4, step: 0.02, format: root.percent },
                    { name: "glassLightAngle", kind: "number", label: "Light from", desc: "Degrees left of straight above (negative: right)", from: -60, to: 60, step: 5, format: v => Math.round(v) + "°" },
                    { name: "launcherOpacity", kind: "number", label: "Launcher and clipboard", desc: "", from: 0.5, to: 0.98, step: 0.02, format: root.percent },
                    { name: "ccOpacity", kind: "number", label: "Control center", desc: "", from: 0.5, to: 0.98, step: 0.02, format: root.percent },
                    { name: "notifOpacity", kind: "number", label: "Notifications", desc: "The grown middle island", from: 0.5, to: 0.98, step: 0.02, format: root.percent },
                    { name: "calendarOpacity", kind: "number", label: "Calendar", desc: "", from: 0.5, to: 0.98, step: 0.02, format: root.percent },
                    { name: "switcherOpacity", kind: "number", label: "Alt+Tab", desc: "", from: 0.5, to: 0.98, step: 0.02, format: root.percent },
                    { name: "sessionOpacity", kind: "number", label: "Power menu", desc: "", from: 0.4, to: 0.98, step: 0.02, format: root.percent },
                    { name: "polkitOpacity", kind: "number", label: "Password dialog", desc: "", from: 0.4, to: 0.98, step: 0.02, format: root.percent },
                    { name: "tooltipOpacity", kind: "number", label: "Bar tips", desc: "", from: 0.5, to: 0.98, step: 0.02, format: root.percent }
                ] },
                { title: "Light and dark", rows: [
                    { name: "themeMode", kind: "choice", label: "Colors", desc: "Auto: light from sunrise to sunset at the weather place",
                      choices: [{ value: "dark", label: "Dark" }, { value: "light", label: "Light" }, { value: "auto", label: "Auto" }] },
                    { name: "themeApps", kind: "bool", label: "Apps follow the wallpaper", desc: "GTK apps (Files, Settings…) in this session; apps already open keep their colors until restarted" }
                ] },
                { title: "Text", rows: [
                    { name: "font", kind: "text", label: "Font", desc: "Any installed font family", placeholder: "Google Sans Flex" },
                    { name: "fontSize", kind: "number", label: "Text size", desc: "Body text; the other steps keep their own sizes", from: 10, to: 18, step: 1, format: root.px },
                    { name: "textScale", kind: "number", label: "Text scale", desc: "All of the shell's text at once", from: 0.85, to: 1.3, step: 0.05, format: root.times },
                    { name: "fontWeight", kind: "choice", label: "Weight", desc: "",
                      choices: [{ value: 400, label: "Regular" }, { value: 500, label: "Medium" }, { value: 600, label: "Semibold" }] },
                    { name: "iconSize", kind: "number", label: "Symbol size", desc: "The icons in the islands", from: 14, to: 24, step: 1, format: root.px }
                ] },
                { title: "App icons", rows: [
                    { name: "appIconStyle", kind: "choice", label: "Style", desc: "Tile: every app icon on the same rounded square (launcher, dock, workspaces, Alt+Tab, notifications…)",
                      choices: [{ value: "tile", label: "Tile" }, { value: "plain", label: "Plain" }] },
                    { name: "appIconTileOpacity", kind: "number", label: "Tile glass", desc: "How solid the tile behind each icon is", from: 0.2, to: 1, step: 0.05, format: root.percent },
                    { name: "appIconInner", kind: "number", label: "Icon on the tile", desc: "How much of the tile the icon fills", from: 0.5, to: 1, step: 0.02, format: root.percent },
                    { name: "appIconRim", kind: "number", label: "Tile edge light", desc: "The thin light along the tile's top edge", from: 0, to: 0.5, step: 0.02, format: root.percent }
                ] },
                { title: "Feel", rows: [
                    { name: "hoverTint", kind: "number", label: "Hover light", desc: "How much a button lights up under the pointer", from: 0, to: 0.2, step: 0.01, format: root.percent },
                    { name: "pressTint", kind: "number", label: "Press light", desc: "", from: 0, to: 0.3, step: 0.01, format: root.percent },
                    { name: "pressScale", kind: "number", label: "Click squish", desc: "1× = none", from: 0.8, to: 1, step: 0.02, format: root.times },
                    { name: "tooltipsEnabled", kind: "bool", label: "Tips on the bar", desc: "What an item is, its state in words and its keys, after a moment's hover" },
                    { name: "tooltipDelay", kind: "number", label: "Tip delay", desc: "The first one; the next ones along the bar come at once", from: 100, to: 1500, step: 50, format: root.ms },
                    { name: "iconFillStates", kind: "bool", label: "Icons fill in when on", desc: "Outlined while off (tiles, speaker, keyboard, rows); off: every icon filled" }
                ] },
                { title: "Corners", rows: [
                    { name: "radiusPanel", kind: "number", label: "Panels", desc: "Launcher, control center, calendar, notifications, Alt+Tab; what's inside follows", from: 12, to: 40, step: 1, format: root.px },
                    { name: "radiusPopup", kind: "number", label: "Popups", desc: "The volume popup", from: 8, to: 36, step: 1, format: root.px },
                    { name: "radiusDialog", kind: "number", label: "Dialogs", desc: "Power menu, password, shortcuts", from: 12, to: 48, step: 1, format: root.px }
                ] },
                { title: "Screen corners", rows: [
                    { name: "cornersEnabled", kind: "bool", label: "Rounded screen corners", desc: "Like a Mac display" },
                    { name: "cornerRadius", kind: "number", label: "Size", desc: "", from: 6, to: 28, step: 1, format: root.px },
                    { name: "cornerColor", kind: "text", label: "Color", desc: "Black blends into the screen's edge", placeholder: "black", commit: t => root.setColor("cornerColor", t) }
                ] }
            ]
        },
        {
            id: "bar", title: "Bar", icon: "view_agenda",
            blurb: "The three islands at the top.",
            groups: [
                { title: "Style", rows: [
                    { name: "barStyle", kind: "choice", label: "Bar", desc: "Islands float apart; the others hold them in one bar: Float a rounded one inside the gaps, Hug against the top edge curving into the screen, Plain a flat strip",
                      choices: [{ value: "islands", label: "Islands" }, { value: "float", label: "Float" }, { value: "hug", label: "Hug" }, { value: "plain", label: "Plain" }] },
                    { name: "barHeight", kind: "number", label: "Bar height", desc: "One bar: how tall it is (Islands use the height below)", from: 30, to: 48, step: 1, format: root.px },
                    { name: "barPad", kind: "number", label: "Bar padding", desc: "One bar: its edge to the middle island", from: 0, to: 8, step: 1, format: root.px },
                    { name: "barOpacity", kind: "number", label: "Bar tint", desc: "One bar: how tinted its glass is", from: 0.2, to: 0.95, step: 0.05, format: root.percent },
                    { name: "barCenterIsland", kind: "bool", label: "Middle island", desc: "One bar: the clock island stays an island of its own" },
                    { name: "barIslandDark", kind: "bool", label: "Dark island", desc: "One bar: the middle island near-black, like a dynamic island (off: glass)" },
                    { name: "barIslandOpacity", kind: "number", label: "Island darkness", desc: "", from: 0.5, to: 1, step: 0.02, format: root.percent },
                    { name: "barIslandCards", kind: "bool", label: "Dark cards", desc: "What grows out of the dark island (notifications, launcher, calendar, the player…) stays dark" },
                    { name: "barIslandCardOpacity", kind: "number", label: "Card darkness", desc: "", from: 0.5, to: 1, step: 0.02, format: root.percent },
                    { name: "barGroups", kind: "bool", label: "Side groups", desc: "One bar: a soft pill behind the left and right things" },
                    { name: "barGroupTint", kind: "number", label: "Group tint", desc: "", from: 0.02, to: 0.2, step: 0.01, format: root.percent }
                ] },
                { title: "Islands", rows: [
                    { name: "islandHeight", kind: "number", label: "Height", desc: "Islands style", from: 28, to: 48, step: 1, format: root.px },
                    { name: "islandRadius", kind: "number", label: "Corners", desc: "Half the height is a full pill", from: 6, to: 24, step: 1, format: root.px },
                    { name: "marginEdge", kind: "number", label: "Gap from the top", desc: "", from: 0, to: 20, step: 1, format: root.px },
                    { name: "marginEnds", kind: "number", label: "Gap at the sides", desc: "", from: 0, to: 40, step: 1, format: root.px },
                    { name: "islandPadding", kind: "number", label: "Inside padding", desc: "Island edge to the first and last thing in it", from: 0, to: 12, step: 1, format: root.px },
                    { name: "islandSpacing", kind: "number", label: "Space between things", desc: "", from: 0, to: 12, step: 1, format: root.px },
                    { name: "itemHeight", kind: "number", label: "Button size", desc: "Hover circles and the workspace area", from: 20, to: 40, step: 1, format: root.px },
                    { name: "startupIntro", kind: "bool", label: "Way in after login", desc: "The wallpaper fades in from dark, then the bar, dock and desktop come in" },
                    { name: "dropInDelay", kind: "number", label: "Drop-in stagger", desc: "At start, between the islands dropping in", from: 0, to: 300, step: 10, format: root.ms }
                ] },
                { title: "Clock", rows: [
                    { name: "clockDate", kind: "choice", label: "Date", desc: "Next to the time",
                      choices: [{ value: "ddd d MMM", label: "Thu 15 Oct" }, { value: "dddd d MMMM", label: "Thursday 15 October" }, { value: "d/M", label: "15/10" }, { value: "", label: "None" }] },
                    { name: "clockLocale", kind: "choice", label: "Date language", desc: "",
                      choices: [{ value: "en_US", label: "English" }, { value: "", label: "System (Tiếng Việt)" }] },
                    { name: "clock24h", kind: "bool", label: "24-hour time", desc: "Off: 12-hour with AM/PM" },
                    { name: "clockSize", kind: "number", label: "Time size", desc: "", from: 12, to: 20, step: 1, format: root.px }
                ] },
                { title: "Music", rows: [
                    { name: "showVisualizer", kind: "bool", label: "Dancing bars", desc: "Next to the song while it plays (cava)" },
                    { name: "visualizerBars", kind: "number", label: "Number of bars", desc: "", from: 3, to: 16, step: 1, format: root.count },
                    { name: "visualizerFps", kind: "number", label: "Smoothness", desc: "How often the bars move; less uses less power", from: 10, to: 30, step: 5, format: v => Math.round(v) + " fps" }
                ] },
                { title: "Workspaces and the rest", rows: [
                    { name: "workspaceStyle", kind: "choice", label: "Workspaces as", desc: "Slots: numbers or app icons; dots: a dot each, the current one a long pill",
                      choices: [{ value: "slots", label: "Slots" }, { value: "dots", label: "Dots" }] },
                    { name: "workspacesShown", kind: "number", label: "Workspaces shown", desc: "At least this many; more appear when used", from: 1, to: 9, step: 1, format: root.count },
                    { name: "workspaceSlot", kind: "number", label: "Workspace size", desc: "", from: 16, to: 36, step: 1, format: root.px },
                    { name: "workspaceIcons", kind: "bool", label: "App icons on workspaces", desc: "A workspace with windows shows their apps instead of its number" },
                    { name: "workspaceIconsMax", kind: "number", label: "Icons per workspace", desc: "More than this shows as +n", from: 1, to: 6, step: 1, format: root.count },
                    { name: "titleMaxWidth", kind: "number", label: "Window title width", desc: "Longest it gets before …", from: 120, to: 500, step: 20, format: root.px },
                    { name: "mediaMaxWidth", kind: "number", label: "Song title width", desc: "", from: 120, to: 400, step: 20, format: root.px },
                    { name: "volumeStep", kind: "number", label: "Volume per scroll", desc: "Scrolling on the volume", from: 0.01, to: 0.1, step: 0.01, format: root.percent },
                    { name: "batteryLow", kind: "number", label: "Battery turns red at", desc: "", from: 5, to: 40, step: 5, format: v => Math.round(v) + "%" },
                    { name: "barHideUnused", kind: "bool", label: "Hide what isn't in use", desc: "The phone while it isn't connected, the on-screen keyboard button outside tablet mode" }
                ] }
            ]
        },
        {
            id: "baritems", title: "Bar items", icon: "dashboard_customize",
            blurb: "What each island holds, top to bottom = left to right. ↑ ↓ change the order, ← → move it to the island next door, ✕ takes it off the bar. An empty island goes away.",
            groups: [
                { title: "Left island", rows: [{ kind: "baritems", key: "barLeft", label: "" }] },
                { title: "Middle island", rows: [{ kind: "baritems", key: "barCenter", label: "" }] },
                { title: "Right island", rows: [{ kind: "baritems", key: "barRight", label: "" }] },
                { title: "Not on the bar", rows: [{ kind: "baritems", label: "" }] },
                { title: "Focus timer", rows: [
                    { name: "focusMinutes", kind: "number", label: "Work", desc: "Add \"Focus timer\" to the bar above", from: 5, to: 120, step: 5, format: v => Math.round(v) + " min" },
                    { name: "focusBreak", kind: "number", label: "Short break", desc: "", from: 1, to: 30, step: 1, format: v => Math.round(v) + " min" },
                    { name: "focusLongBreak", kind: "number", label: "Long break", desc: "", from: 5, to: 60, step: 5, format: v => Math.round(v) + " min" },
                    { name: "focusRounds", kind: "number", label: "Long break after", desc: "Rounds of work", from: 2, to: 8, step: 1, format: v => Math.round(v) + " rounds" },
                    { name: "focusSilent", kind: "bool", label: "Silent while working", desc: "Notifications wait until the break" }
                ] },
                { title: "System stats", rows: [
                    { name: "statsInterval", kind: "number", label: "Update every", desc: "Only read while one is on the bar", from: 1000, to: 10000, step: 500, format: root.ms },
                    { name: "statsMemoryAs", kind: "choice", label: "Memory as", desc: "",
                      choices: [{ value: "percent", label: "Percent" }, { value: "gb", label: "GB" }] },
                    { name: "statsWarnCpu", kind: "number", label: "CPU turns red at", desc: "", from: 50, to: 100, step: 5, format: v => Math.round(v) + "%" },
                    { name: "statsWarnMemory", kind: "number", label: "Memory turns red at", desc: "", from: 50, to: 100, step: 5, format: v => Math.round(v) + "%" },
                    { name: "statsWarnTemp", kind: "number", label: "Temperature turns red at", desc: "", from: 60, to: 100, step: 5, format: v => Math.round(v) + " °C" },
                    { name: "statsWarnDisk", kind: "number", label: "Disk turns red at", desc: "", from: 50, to: 100, step: 5, format: v => Math.round(v) + "%" },
                    { name: "statsClickCommand", kind: "text", label: "Open btop button runs", desc: "The button at the bottom of the System popup; empty = btop in the terminal (or htop, Resources…)", placeholder: "foot -e btop" }
                ] },
                { title: "System popup (click a stat)", rows: [
                    { name: "sysmonInterval", kind: "number", label: "Update every", desc: "Only while it's open; the processes every other time", from: 500, to: 3000, step: 250, format: root.ms },
                    { name: "sysmonProcessCount", kind: "number", label: "Apps shown", desc: "", from: 3, to: 10, step: 1, format: v => Math.round(v) },
                    { name: "sysmonSortBy", kind: "choice", label: "Apps sorted by", desc: "How it opens; click a column (or C / M) to switch",
                      choices: [{ value: "cpu", label: "CPU" }, { value: "memory", label: "Memory" }] },
                    { name: "sysmonWidth", kind: "number", label: "Width", desc: "", from: 340, to: 560, step: 10, format: root.px },
                    { name: "sysmonOpacity", kind: "number", label: "Glass", desc: "", from: 0.4, to: 1, step: 0.02, format: root.percent }
                ] },
                { title: "Privacy dots and typing language", rows: [
                    { name: "privacyQuietSharing", kind: "bool", label: "Quiet while sharing the screen", desc: "New notifications go to the list without popping up while an app shares the screen or you record it (urgent ones still show)" },
                    { name: "privacyCamera", kind: "bool", label: "Camera dot", desc: "Add \"Privacy dots\" to the bar above; green while an app has the camera open" },
                    { name: "privacyCameraPoll", kind: "number", label: "Look at the camera every", desc: "Its power state only (a tiny read); which apps use it is looked up when it starts", from: 1000, to: 10000, step: 500, format: root.ms },
                    { name: "osdIme", kind: "bool", label: "Typing language popup", desc: "English / Tiếng Việt when you switch (Super+Space); the tray shows EN / VI either way" }
                ] },
                { title: "Updates", rows: [
                    { name: "updatesInterval", kind: "number", label: "Check every", desc: "Add \"Updates\" to the bar above; it shows only while some wait. Only checked while it's on the bar and online", from: 0, to: 24, step: 1, format: v => v <= 0 ? "Only when asked" : Math.round(v) + " h" },
                    { name: "updatesFirstDelay", kind: "number", label: "First check after login", desc: "Gives the network and the login a moment", from: 1, to: 30, step: 1, format: v => Math.round(v) + " min" },
                    { name: "updatesClick", kind: "choice", label: "Click the item for", desc: "Panel: the lists, Arch news, and Update right under the item (it installs the repo packages and Flatpaks itself; AUR ones go to the terminal). Right click always checks now",
                      choices: [{ value: "panel", label: "Panel" }, { value: "terminal", label: "Terminal" }] },
                    { name: "updatesFlatpak", kind: "bool", label: "Flatpak too", desc: "Counts Flatpak apps and runtimes, and updates them after the packages (the panel's Update, and after the command)" },
                    { name: "updatesCommand", kind: "text", label: "Update command", desc: "Runs in a terminal: the panel's In terminal, or the click when it opens the terminal", placeholder: "paru" },
                    { name: "updatesNews", kind: "bool", label: "Arch news in the panel", desc: "News from archlinux.org newer than your last full upgrade (they sometimes say what to do by hand); read at most every 3 hours" },
                    { name: "updatesPanelWidth", kind: "number", label: "Panel width", desc: "", from: 320, to: 480, step: 10, format: root.px },
                    { name: "updatesHeadsUp", kind: "text", label: "Heads-up for", desc: "Named in the tip and the panel (and the icon turns accent) when they're among the updates; the panel's Update asks again, listing them; * matches anything, commas between; empty = the usual ones",
                      placeholder: "quickshell*, linux-*, …", commit: t => root.setList("updatesHeadsUp", t) },
                    { kind: "action", label: "Check now", desc: "", button: "Check", run: () => Updates.check("settings"),
                      status: () => Updates.checking ? "Checking…" : Updates.failed !== "" ? Updates.failed
                          : Updates.checkedAt > 0 ? (Updates.count === 0 ? "Up to date" : Updates.count + " waiting (" + Updates.summary + ")") + ", checked " + Updates.ago(Updates.checkedAt) : "Not checked yet" }
                ] },
                { title: "", rows: [
                    { kind: "action", label: "Default bar", desc: "Every island back to how it came", button: "Reset", confirm: true,
                      run: () => { Settings.reset("barLeft"); Settings.reset("barCenter"); Settings.reset("barRight"); } }
                ] }
            ]
        },
        {
            id: "dock", title: "Dock", icon: "dock_to_bottom",
            blurb: "Pinned apps first, then the ones running. Right-click an icon to pin or unpin it.",
            groups: [
                { title: "Behaviour", rows: [
                    { name: "dockBehavior", kind: "choice", label: "Show the dock", desc: "Auto-hide: touch the bottom edge under it to bring it back. Smart: shown on an empty workspace, hidden when windows are open",
                      choices: [{ value: "always", label: "Always" }, { value: "autohide", label: "Auto-hide" }, { value: "smart", label: "Smart" }] },
                    { name: "dockHideDelay", kind: "number", label: "Hide after", desc: "Once the pointer leaves it", from: 0, to: 3000, step: 100, format: root.ms },
                    { name: "dockRevealZone", kind: "number", label: "Edge that brings it back", desc: "How close to the bottom edge the pointer has to be", from: 1, to: 10, step: 1, format: root.px },
                    { name: "dockReserve", kind: "bool", label: "Keep windows above the dock", desc: "When it's always shown; off: windows can go under it" }
                ] },
                { title: "Open windows", rows: [
                    { name: "dockRunningDots", kind: "bool", label: "Dots under running apps", desc: "One per window (up to 3); the focused window's is a wide accent pill" },
                    { name: "dockPreviews", kind: "bool", label: "Window previews", desc: "Rest the pointer on a running app: a live picture of each of its windows. Click one to go there, middle-click or ✕ to close it" },
                    { name: "dockPreviewDelay", kind: "number", label: "Show previews after", desc: "Resting on the icon", from: 0, to: 1500, step: 50, format: root.ms },
                    { name: "dockPreviewSize", kind: "number", label: "Preview size", desc: "Height of each picture", from: 80, to: 260, step: 10, format: root.px }
                ] },
                // Dock badges
                { title: "Badges", rows: [
                    { name: "dockBadges", kind: "bool", label: "Unread counts on icons", desc: "A red number on an app with unread messages (Discord, Telegram…)" },
                    { name: "dockBadgeSource", kind: "choice", label: "Count from", desc: "Apps: what the app itself tells docks (not every app does). Notifications: its unread notifications. Both: the app's own count when it gives one",
                      choices: [{ value: "both", label: "Both" }, { value: "apps", label: "Apps" }, { value: "notifications", label: "Notifications" }] },
                    { name: "dockBadgeProgress", kind: "bool", label: "Progress bar", desc: "A thin bar on the icon while the app says it's busy (a download, a copy)" }
                ] },
                { title: "Look", rows: [
                    { name: "dockIconSize", kind: "number", label: "Icon size", desc: "", from: 28, to: 64, step: 2, format: root.px },
                    { name: "dockMagnify", kind: "number", label: "Magnification", desc: "How big the icon under the pointer grows (1× = off)", from: 1, to: 2, step: 0.05, format: root.times },
                    { name: "dockMagnifyRange", kind: "number", label: "Magnification reach", desc: "How many icons around it grow too", from: 1, to: 5, step: 0.1, format: v => v.toFixed(1) + " icons" },
                    { name: "dockSpacing", kind: "number", label: "Space between icons", desc: "", from: 0, to: 20, step: 1, format: root.px },
                    { name: "dockPaddingMain", kind: "number", label: "Padding at the ends", desc: "", from: 0, to: 30, step: 1, format: root.px },
                    { name: "dockPaddingCross", kind: "number", label: "Padding above and below", desc: "", from: 0, to: 20, step: 1, format: root.px },
                    { name: "dockMarginEdge", kind: "number", label: "Gap from the bottom", desc: "", from: 0, to: 24, step: 1, format: root.px },
                    { name: "dockRadius", kind: "number", label: "Corners", desc: "", from: 0, to: 32, step: 1, format: root.px },
                    { name: "dockDark", kind: "bool", label: "Dark dock", desc: "Near-black, like the bar's middle island (Bar → Style); its label, previews and menu too" },
                    { name: "dockOpacity", kind: "number", label: "Glass", desc: "When it isn't dark", from: 0.2, to: 0.95, step: 0.05, format: root.percent }
                ] }
            ]
        },
        {
            id: "notifications", title: "Notifications", icon: "notifications",
            blurb: "They grow out of the middle island; the bell has the list.",
            groups: [
                { title: "", rows: [
                    { kind: "dnd", label: "Silent", desc: "No popups or sound; they still land in the list" },
                    { name: "notifSound", kind: "bool", label: "Sound", desc: "A short sound for each new one" },
                    { name: "notifBadge", kind: "choice", label: "Unread on the bell", desc: "The dot turns red while an urgent one is unread",
                      choices: [{ value: "dot", label: "A dot" }, { value: "count", label: "The number" }] },
                    { name: "notifTimeout", kind: "number", label: "Show for", desc: "Apps can ask for other times", from: 2000, to: 15000, step: 500, format: root.ms },
                    { name: "notifMaxPopups", kind: "number", label: "Waiting in line", desc: "Older ones go straight to the list", from: 1, to: 6, step: 1, format: root.count },
                    { name: "notifBodyLines", kind: "number", label: "Text lines", desc: "Before you hover (hover shows 6)", from: 1, to: 6, step: 1, format: root.count },
                    { name: "notifHistoryMax", kind: "number", label: "Kept in the list", desc: "Also after a restart", from: 20, to: 500, step: 20, format: root.count },
                    { name: "notifGroupByApp", kind: "bool", label: "Group by app", desc: "The list shows one card per app; click it to see the rest" },
                    { name: "notifReply", kind: "bool", label: "Reply in place", desc: "A Reply button when the app allows it (chat apps)" }
                ] },
                { title: "Silent hours", rows: [
                    { name: "dndSchedule", kind: "bool", label: "Silent at night", desc: "Turns Silent on and off by itself; a change by hand sticks until the next time",
                      status: () => !Style.dndSchedule ? "" : Notifs.inDndHours ? "Silent now, until " + Style.dndTo : "Next: from " + Style.dndFrom },
                    { name: "dndFrom", kind: "text", label: "From", desc: "24-hour time", placeholder: "22:00",
                      status: () => Notifs.minutesOf(Style.dndFrom) < 0 ? "Not a time: use 24-hour time like 22:00" : "" },
                    { name: "dndTo", kind: "text", label: "Until", desc: "24-hour time", placeholder: "07:00",
                      status: () => Notifs.minutesOf(Style.dndTo) < 0 ? "Not a time: use 24-hour time like 07:00" : "" },
                    { name: "dndFullscreen", kind: "bool", label: "Quiet while fullscreen", desc: "Games and films: new ones go to the list without a popup or sound; urgent ones still show",
                      status: () => Notifs.fullscreenQuiet ? "Quiet now: " + (Fullscreen.appId || "a window") + " is fullscreen" : "" }
                ] },
                { title: "Claude Code", rows: [
                    { name: "agentsNotify", kind: "bool", label: "When a session is done", desc: "Or waits for you (a permission prompt looks the same); not while you're in its window. Show goes there",
                      status: () => Agents.sessions.length === 0 ? "" : Agents.sessions.length + " now: " + Agents.workingCount + " working, " + Agents.waitingCount + " waiting for you" },
                    { name: "agentsHold", kind: "number", label: "Once stopped for", desc: "Shorter stops, between steps, don't count", from: 1, to: 15, step: 1, format: v => Math.round(v) + " s" },
                    { name: "agentsSound", kind: "bool", label: "Sound", desc: "A chime with it (not while Silent)" }
                ] },
                // One row per app with a rule (Notifs.rules only changes when the rules do).
                { title: "Per app", rows: Notifs.rules.length === 0
                    ? [{ kind: "info", label: "No apps muted", text: () => "Right-click a notification (or an app in the list): Mute, or List only" }]
                    : Notifs.rules.map(r => ({
                        kind: "action", label: r.app, button: "Remove", run: () => Notifs.setRule(r.app, ""),
                        desc: r.rule === "mute" ? "Muted: not shown, not kept" : "List only: in the list, no popup or sound"
                    })) },
                { title: "On the lock screen", rows: [
                    { name: "lockNotifCounts", kind: "bool", label: "While you were away", desc: "Under the time: each app's icon and how many it sent since it locked, never what they say" },
                    { name: "lockNotifNames", kind: "bool", label: "App names", desc: "Off: only the icons and the total" }
                ] },
                { title: "Look", rows: [
                    { name: "notifWidth", kind: "number", label: "Width", desc: "The grown island and the cards in the list", from: 320, to: 560, step: 10, format: root.px },
                    { name: "notifMaxHeight", kind: "number", label: "Tallest", desc: "", from: 160, to: 400, step: 10, format: root.px },
                    { name: "notifIslandRadius", kind: "number", label: "Island corners", desc: "", from: 12, to: 40, step: 1, format: root.px },
                    { name: "notifRadius", kind: "number", label: "Card corners", desc: "In the list", from: 8, to: 32, step: 1, format: root.px }
                ] }
            ]
        },
        {
            id: "activities", title: "Live activities", icon: "bubble_chart",
            blurb: "The middle island grows for a moment when something happens; a bubble beside it while something goes on.",
            groups: [
                { title: "", rows: [
                    { name: "activitiesEnabled", kind: "bool", label: "Live activities", desc: "Try one: qs -c mine ipc call activities preview charging" },
                    { name: "activityDuration", kind: "number", label: "Show for", desc: "Hover keeps it open", from: 1500, to: 6000, step: 250, format: root.ms }
                ] },
                { title: "Moments", rows: [
                    { name: "activityCharging", kind: "bool", label: "Charger", desc: "Plugged in or unplugged, with the time left" },
                    { name: "activityBluetooth", kind: "bool", label: "Headphones and speakers", desc: "Bluetooth audio connecting or leaving, with its battery" },
                    { name: "activityScreenshot", kind: "bool", label: "Screenshots", desc: "Instead of the popup; the notification still goes to the list" },
                    { name: "activityClipboard", kind: "bool", label: "Copies", desc: "What you copied (not while the screen is shared or recorded)" },
                    { name: "activityWifi", kind: "bool", label: "Wi-Fi", desc: "Connected or disconnected" },
                    { name: "activityFocus", kind: "bool", label: "Focus timer", desc: "Break time and back to work, instead of a notification" }
                ] },
                { title: "Bubble", rows: [
                    { name: "activityBubble", kind: "bool", label: "In the middle island", desc: "Screen recording, the focus timer and Claude Code at work, in front of the clock" },
                    { name: "activityAgents", kind: "bool", label: "Claude Code", desc: "Sessions working or waiting for you, in the bubble" }
                ] }
            ]
        },
        {
            id: "sounds", title: "Sounds", icon: "volume_up",
            blurb: "Small sounds for things the shell does. The files: common/sounds.js.",
            groups: [
                { title: "", rows: [
                    { name: "soundVolume", kind: "number", label: "Volume", desc: "Of the speaker's own volume; 0% = no sounds", from: 0, to: 1, step: 0.05, format: root.percent }
                ] },
                { title: "Play a sound for", rows: [
                    { name: "soundVolumeTick", kind: "bool", label: "Volume changes", desc: "A soft click with the keys or scrolling on the bar" },
                    { name: "soundScreenshot", kind: "bool", label: "Screenshots", desc: "A shutter when one is saved" },
                    { name: "soundRecord", kind: "bool", label: "Screen recording", desc: "When it starts and stops" },
                    { name: "soundLock", kind: "bool", label: "Locking and unlocking", desc: "" },
                    { name: "soundPower", kind: "bool", label: "Charger", desc: "Plugged in or out" },
                    { name: "soundDevices", kind: "bool", label: "Bluetooth devices", desc: "Connecting and going away" },
                    { name: "notifSound", kind: "bool", label: "New notifications", desc: "Also under Notifications" }
                ] }
            ]
        },
        {
            id: "launcher", title: "Launcher & windows", icon: "search",
            blurb: "Super: the middle island becomes a search bar. Super+V: the clipboard. Alt+Tab: your windows, most recent first. Super+/: every shortcut. Your apps come back at login.",
            groups: [
                { title: "Launcher", rows: [
                    { name: "launcherRows", kind: "number", label: "Results shown", desc: "Before the list scrolls", from: 4, to: 12, step: 1, format: root.count },
                    { name: "launcherFavorites", kind: "text", label: "Favorites", desc: "Shown before you type: app ids, with commas", placeholder: "foot, zen, …", commit: t => root.setList("launcherFavorites", t) },
                    { name: "launcherWidth", kind: "number", label: "Width", desc: "", from: 440, to: 800, step: 20, format: root.px },
                    { name: "launcherRowHeight", kind: "number", label: "Row height", desc: "", from: 36, to: 64, step: 2, format: root.px },
                    { name: "launcherRadius", kind: "number", label: "Corners", desc: "", from: 12, to: 40, step: 1, format: root.px }
                ] },
                { title: "Search modes", rows: [
                    { name: "launcherEmoji", kind: "bool", label: "Emoji", desc: "Type : and a name (:fire); Enter copies it" },
                    { name: "launcherFiles", kind: "bool", label: "Files", desc: "Type / or ~ and part of a name; Ctrl+Enter opens its folder" },
                    { name: "fileSearchRoot", kind: "text", label: "Look for files in", desc: "A folder; ~ is your home", placeholder: "~" },
                    { name: "launcherWeb", kind: "bool", label: "Web", desc: "Type ? to search; a web address opens it" },
                    { name: "webSearchUrl", kind: "text", label: "Search engine", desc: "%s is what you typed", placeholder: "https://www.google.com/search?q=%s" }
                ] },
                // Launcher: translate (tr hello)
                { title: "Translate", rows: [
                    { name: "launcherTranslate", kind: "bool", label: "Translate with tr", desc: "Type tr and some text (tr ja: hello for Japanese); Enter copies the translation. The text goes to Google Translate, only once you stop typing" }
                ] },
                // Launcher: app grid
                { title: "App grid", rows: [
                    { name: "launcherGridInTablet", kind: "bool", label: "Open as a grid in tablet mode", desc: "Every app as a big tile, with groups on top. The ▦ button in the launcher (or mine launcher grid) shows it any time" },
                    { name: "launcherGridIconSize", kind: "number", label: "Grid icon size", desc: "A fifth bigger in tablet mode", from: 44, to: 96, step: 4, format: root.px }
                ] },
                { title: "Clipboard", rows: [
                    { name: "clipAutoPaste", kind: "bool", label: "Paste right away", desc: "Picking an entry pastes it into the app you were in" },
                    { name: "clipSkipSecrets", kind: "bool", label: "Leave out secrets", desc: "API keys, tokens, private keys, and codes your phone just showed" },
                    { name: "clipRows", kind: "number", label: "Entries shown", desc: "Before the list scrolls", from: 4, to: 12, step: 1, format: root.count },
                    { name: "clipWidth", kind: "number", label: "Width", desc: "", from: 400, to: 800, step: 20, format: root.px },
                    { name: "clipRowHeight", kind: "number", label: "Row height", desc: "", from: 40, to: 72, step: 2, format: root.px }
                ] },
                { title: "Alt+Tab", rows: [
                    { name: "switcherIdleCommit", kind: "number", label: "Quick Alt+Tab switches after", desc: "When Alt is let go too fast for the switcher to notice", from: 300, to: 2000, step: 100, format: root.ms },
                    { name: "switcherIconSize", kind: "number", label: "Icon size", desc: "", from: 36, to: 72, step: 2, format: root.px },
                    { name: "switcherCell", kind: "number", label: "Space per window", desc: "", from: 60, to: 120, step: 2, format: root.px },
                    { name: "switcherRadius", kind: "number", label: "Corners", desc: "", from: 12, to: 40, step: 1, format: root.px }
                ] },
                { title: "Apps at login", rows: [
                    { name: "restoreApps", kind: "bool", label: "Reopen your apps", desc: "The ones open when you logged out or shut down, each on its workspace" },
                    { name: "restoreAppsExclude", kind: "text", label: "Never reopen", desc: "App ids, with commas", placeholder: "foot, …", commit: t => root.setList("restoreAppsExclude", t) },
                    { kind: "info", label: "Next login", text: () => Style.restoreApps ? AppRestore.summary : "Off" }
                ] },
                { title: "Overview", rows: [
                    { kind: "action", label: "Every window", desc: "Super+O, the hot corner or 4 fingers up · drag a window onto another workspace to move it", button: "Show", run: () => Panels.overview() },
                    { name: "overviewHotCorner", kind: "choice", label: "Hot corner", desc: "Rest the pointer there to open it",
                      choices: [{ value: "off", label: "Off" }, { value: "top-left", label: "Top left" }, { value: "top-right", label: "Top right" }, { value: "bottom-left", label: "Bottom left" }, { value: "bottom-right", label: "Bottom right" }] },
                    { name: "overviewHotCornerDelay", kind: "number", label: "Rest in the corner for", desc: "So passing by doesn't open it", from: 0, to: 600, step: 50, format: root.ms },
                    { name: "overviewShowAll", kind: "bool", label: "All 9 workspaces", desc: "Off: the ones with windows, yours, and a new one" },
                    { name: "overviewColumns", kind: "number", label: "Workspaces per row", desc: "At most", from: 2, to: 5, step: 1, format: root.count },
                    { name: "overviewGap", kind: "number", label: "Space between them", desc: "", from: 8, to: 60, step: 2, format: root.px },
                    { name: "overviewCardRadius", kind: "number", label: "Corners", desc: "Of a workspace", from: 0, to: 36, step: 1, format: root.px },
                    { name: "overviewLive", kind: "bool", label: "Pictures of the windows", desc: "Off: the apps' icons (lighter)" },
                    { name: "overviewRefresh", kind: "number", label: "Update the pictures every", desc: "Your workspace's; the others about 4 times slower. 0 = only when it opens", from: 0, to: 3000, step: 100, format: v => v < 1 ? "Never" : root.ms(v) },
                    { name: "overviewDim", kind: "number", label: "Darken the screen behind", desc: "", from: 0, to: 0.8, step: 0.05, format: root.percent }
                ] },
                { title: "Shortcut cheat sheet", rows: [
                    { kind: "action", label: "Every shortcut", desc: "Super+/ · read from mango's config, type to search", button: "Show", run: () => Panels.cheatsheet() },
                    { name: "cheatSheetColumns", kind: "number", label: "Columns", desc: "Auto: as many as fit", from: 0, to: 4, step: 1, format: v => v < 1 ? "Auto" : root.count(v) },
                    { name: "cheatSheetColumnWidth", kind: "number", label: "Column width", desc: "", from: 300, to: 480, step: 10, format: root.px },
                    { name: "cheatSheetRowHeight", kind: "number", label: "Row height", desc: "", from: 24, to: 40, step: 1, format: root.px },
                    { name: "cheatSheetChipHeight", kind: "number", label: "Key size", desc: "", from: 18, to: 30, step: 1, format: root.px },
                    { name: "cheatSheetRadius", kind: "number", label: "Corners", desc: "", from: 12, to: 40, step: 1, format: root.px },
                    { name: "cheatSheetOpacity", kind: "number", label: "Glass", desc: "", from: 0.5, to: 0.98, step: 0.02, format: root.percent },
                    { name: "cheatSheetDim", kind: "number", label: "Darken the screen behind", desc: "0% = off", from: 0, to: 0.6, step: 0.05, format: root.percent }
                ] }
            ]
        },
        {
            id: "panels", title: "Popups & panels", icon: "widgets",
            blurb: "The control center, the Now Playing card, the volume and brightness popup, the power menu, the password dialog, your phone and Tailscale.",
            groups: [
                { title: "Control center", rows: [
                    { name: "ccWidth", kind: "number", label: "Width", desc: "", from: 340, to: 520, step: 10, format: root.px },
                    { name: "ccRadius", kind: "number", label: "Corners", desc: "", from: 12, to: 40, step: 1, format: root.px },
                    { name: "ccPadding", kind: "number", label: "Padding", desc: "Card edge to the tiles; the tiles' corners follow", from: 6, to: 24, step: 1, format: root.px },
                    { name: "ccTileHeight", kind: "number", label: "Tile height", desc: "Wi-Fi, Bluetooth, Silent…", from: 48, to: 80, step: 2, format: root.px },
                    { name: "ccSliderHeight", kind: "number", label: "Slider height", desc: "", from: 28, to: 52, step: 2, format: root.px },
                    { name: "ccAppVolumes", kind: "bool", label: "Volume per app", desc: "Under the volume slider, when apps are playing sound" }
                ] },
                { title: "Now Playing card", rows: [
                    { name: "nowPlayingEnabled", kind: "bool", label: "Click the song for the player", desc: "The middle island grows into it. Off: the click plays or pauses (the little cover always does)" },
                    { name: "nowPlayingTint", kind: "number", label: "Cover color in the glass", desc: "0 = plain glass", from: 0, to: 0.8, step: 0.05, format: root.percent },
                    { name: "nowPlayingWidth", kind: "number", label: "Width", desc: "", from: 340, to: 560, step: 10, format: root.px },
                    { name: "nowPlayingArtSize", kind: "number", label: "Cover size", desc: "", from: 64, to: 160, step: 4, format: root.px },
                    { name: "nowPlayingOpacity", kind: "number", label: "Glass", desc: "", from: 0.5, to: 0.98, step: 0.02, format: root.percent },
                    { name: "nowPlayingRadius", kind: "number", label: "Corners", desc: "The cover's follow", from: 12, to: 40, step: 1, format: root.px },
                    { name: "nowPlayingSeekStep", kind: "number", label: "← → jump", desc: "Seconds per key press", from: 2, to: 30, step: 1, format: v => Math.round(v) + " s" }
                ] },
                { title: "Lyrics", rows: [
                    { name: "lyricsEnabled", kind: "bool", label: "Lyrics", desc: "Looked up on lrclib.net (it gets the song's title, artist, album and length) and kept on this computer" },
                    { name: "lyricsInCard", kind: "bool", label: "In the Now Playing card", desc: "Under the song, the line being sung lit up; click a line to go there" },
                    { name: "lyricsInBar", kind: "bool", label: "In the bar", desc: "The line being sung in place of the song's name, for songs with timed lyrics" },
                    { name: "lyricsOnDesktop", kind: "bool", label: "On the desktop", desc: "The song's lines gliding by in the music card on the desktop (timed lyrics only); click a line to go there" },
                    { name: "lyricsBrowsers", kind: "bool", label: "From browsers", desc: "Also look up what plays in Brave, Firefox, … (YouTube titles go to lrclib.net too, and most aren't songs)" },
                    { name: "lyricsBarWidth", kind: "number", label: "Bar line width", desc: "Fixed, so the island stays put while lines change", from: 160, to: 420, step: 10, format: root.px },
                    { name: "lyricsCardHeight", kind: "number", label: "Card lyrics height", desc: "", from: 120, to: 320, step: 8, format: root.px },
                    { name: "lyricsDesktopHeight", kind: "number", label: "Desktop lyrics height", desc: "", from: 90, to: 320, step: 10, format: root.px },
                    { name: "lyricsDesktopBlur", kind: "number", label: "Desktop lyrics edge blur", desc: "Where the lines fade out at the top and bottom; 0 = none", from: 0, to: 8, step: 0.5, format: root.halfPx },
                    { name: "lyricsOffset", kind: "number", label: "Timing", desc: "Lines this much earlier (below 0: later)", from: -2, to: 2, step: 0.1, format: v => (v > 0.04 ? "+" : "") + v.toFixed(1) + " s" },
                    { kind: "action", label: "This song's lyrics", desc: "Wrong or missing? Look them up again", button: "Look again", run: () => Lyrics.reload() }
                ] },
                { title: "Volume and brightness popup", rows: [
                    { name: "osdHideDelay", kind: "number", label: "Stays for", desc: "After the last change", from: 500, to: 5000, step: 100, format: root.ms },
                    { name: "osdTiling", kind: "bool", label: "Tiling layout changes", desc: "Show the layout's name when you switch it (Super+Alt+J)" },
                    { name: "osdWidth", kind: "number", label: "Width", desc: "", from: 200, to: 400, step: 10, format: root.px },
                    { name: "osdHeight", kind: "number", label: "Height", desc: "", from: 36, to: 64, step: 2, format: root.px },
                    { name: "osdGap", kind: "number", label: "Gap under the islands", desc: "", from: 0, to: 24, step: 1, format: root.px }
                ] },
                { title: "Volume popup", rows: [
                    { name: "volumePopup", kind: "bool", label: "Click the speaker for the volume popup", desc: "Right under the icon. Off: the click mutes (middle click always does)" },
                    { name: "volumePopupInput", kind: "bool", label: "Microphone", desc: "Its level, and its devices when there's more than one" },
                    { name: "volumePopupWidth", kind: "number", label: "Width", desc: "", from: 240, to: 420, step: 10, format: root.px },
                    { name: "volumePopupRadius", kind: "number", label: "Corners", desc: "", from: 8, to: 36, step: 1, format: root.px }
                ] },
                { title: "Power menu", rows: [
                    { name: "sessionConfirmMs", kind: "number", label: "Time to press again", desc: "Restart, Shut down and Log out ask twice", from: 1000, to: 10000, step: 500, format: root.ms },
                    { name: "sessionButtonSize", kind: "number", label: "Button size", desc: "", from: 64, to: 128, step: 4, format: root.px },
                    { name: "sessionDim", kind: "number", label: "Darken behind", desc: "", from: 0, to: 0.8, step: 0.05, format: root.percent }
                ] },
                { title: "Settings window", rows: [
                    { name: "settingsSectionColors", kind: "bool", label: "Colored section icons", desc: "Each section's icon on its own colored square" },
                    { name: "settingsOpacity", kind: "number", label: "Window glass", desc: "How tinted the window is over the blur behind it", from: 0.4, to: 1, step: 0.02, format: root.percent },
                    { name: "settingsSidebarOpacity", kind: "number", label: "Sidebar glass", desc: "", from: 0, to: 0.9, step: 0.02, format: root.percent },
                    { name: "settingsCardOpacity", kind: "number", label: "Group glass", desc: "", from: 0, to: 0.9, step: 0.02, format: root.percent },
                    { name: "settingsCardRadius", kind: "number", label: "Group corners", desc: "", from: 6, to: 28, step: 1, format: root.px },
                    { name: "settingsWindowRadius", kind: "number", label: "Window corners", desc: "mango's border_radius; the sidebar's corners follow it", from: 0, to: 30, step: 1, format: root.px }
                ] },
                { title: "Password dialog", rows: [
                    { name: "polkitWidth", kind: "number", label: "Width", desc: "", from: 360, to: 600, step: 10, format: root.px },
                    { name: "polkitDim", kind: "number", label: "Darken behind", desc: "", from: 0, to: 0.8, step: 0.05, format: root.percent }
                ] },
                { title: "Phone (KDE Connect)", rows: [
                    { kind: "info", label: "Your phone", text: () => !Phone.known ? "Checking…"
                        : !Phone.installed ? "Not installed: sudo pacman -S kdeconnect, the KDE Connect app on the phone, and ports 1714–1764 open in ufw"
                        : Phone.device ? Phone.device.name + " · " + Phone.summary : Phone.summary },
                    { name: "ccPhone", kind: "bool", label: "Phone tile in the control center", desc: "Battery, ring it, send files or the clipboard, pair" },
                    { name: "phoneDevice", kind: "text", label: "Which phone", desc: "Its name, if more than one is paired; empty = the first", placeholder: "Pixel 8" },
                    { name: "phoneRefresh", kind: "number", label: "Check every", desc: "While the bar item or the control center shows it", from: 10, to: 120, step: 5, format: root.after },
                    { name: "phoneBatteryWarn", kind: "number", label: "Red under", desc: "The bar item's battery (\"Phone\" in Bar items)", from: 0, to: 50, step: 5,
                      format: v => v <= 0 ? "Never" : Math.round(v) + "%" },
                    { kind: "action", label: "Check again", desc: "Ask KDE Connect now", button: "Check", run: () => Phone.refresh() }
                ] },
                { title: "Tailscale", rows: [
                    { kind: "info", label: "Tailscale", text: () => !Tailscale.known ? "Checking…"
                        : !Tailscale.installed ? "Not installed: sudo pacman -S tailscale, then sudo systemctl enable --now tailscaled and tailscale up"
                        : Tailscale.summary + (Tailscale.tailnet !== "" ? " · " + Tailscale.tailnet : "") },
                    { name: "ccTailscale", kind: "bool", label: "Tailscale tile in the control center", desc: "On and off, your devices, the exit node" },
                    { kind: "action", label: "Turn it on and off from the shell", desc: "Needs sudo once (the shell can't): copies the command that makes you Tailscale's operator", button: "Copy command",
                      run: () => Tailscale.copyOperatorCommand(),
                      status: () => !Tailscale.prefsKnown ? ""
                          : Tailscale.canControl ? "Done: you're Tailscale's operator"
                          : "To do: " + Tailscale.operatorCommand + " in a terminal" },
                    { name: "tailscaleCopy", kind: "choice", label: "Click a device to copy", desc: "Right click (or a long press): the other one",
                      choices: [{ value: "ip", label: "Its IP" }, { value: "name", label: "Its name" }] },
                    { name: "tailscaleHideAfterDays", kind: "number", label: "Fold away devices offline for", desc: "Under \"older devices\" on the page", from: 0, to: 180, step: 5,
                      format: v => v <= 0 ? "Never" : Math.round(v) + " days" },
                    { name: "tailscalePollOpen", kind: "number", label: "Check every (control center open)", desc: "", from: 2, to: 30, step: 1, format: v => Math.round(v) + " s" },
                    { name: "tailscalePollBar", kind: "number", label: "Check every (bar item)", desc: "While \"Tailscale\" is in Bar items", from: 15, to: 600, step: 15, format: root.after }
                ] },
                // Switch to GNOME (scripts/switch-session.sh).
                { title: "Switch to GNOME", rows: [
                    { name: "sessionGnome", kind: "bool", label: "Switch to GNOME in the power menu", desc: "Logs out with GNOME already picked on the login screen (you still type your password)" }
                ] },
                // Restart to Windows (services/WindowsBoot.qml).
                { title: "Restart to Windows", rows: [
                    { name: "sessionWindows", kind: "bool", label: "Restart to Windows in the power menu", desc: "Asks for your password, starts Windows once, the next start is Linux again" },
                    { kind: "info", label: "Windows entry", text: () => !WindowsBoot.known ? "Checking…"
                        : WindowsBoot.entry === "" ? "None in the firmware (efibootmgr)"
                        : "Boot" + WindowsBoot.entry + " · Windows Boot Manager" + (WindowsBoot.bootNext !== "" ? " · next start: Boot" + WindowsBoot.bootNext : "") }
                ] },
                // USB drives (services/Drives.qml, bar/DrivesItem.qml).
                { title: "USB drives", rows: [
                    { name: "drivesWatch", kind: "bool", label: "Watch for USB drives", desc: "The bar item (\"USB drives\" in Bar items) while one is plugged in: size, free space, Open and Eject" },
                    { name: "drivesNotify", kind: "bool", label: "Notification when one is plugged in", desc: "With Open and Eject" },
                    { name: "drivesPopupWidth", kind: "number", label: "Popup width", desc: "", from: 280, to: 440, step: 10, format: root.px },
                    { kind: "info", label: "Plugged in", text: () => Drives.count === 0 ? "None" : Drives.drives.map(d => d.title + " (" + d.sizeText + ")").join(" · ") }
                ] }
            ]
        },
        // ---- Control center (ctl): its tiles, the hotspot, name that song ---------------
        {
            id: "controlcenter", title: "Control center", icon: "toggle_on",
            blurb: "The tiles at the top of the control center, left to right, row by row. Also from the control center itself: Edit under the tiles (drag to move, − to take away, Add tiles). Sliders and the player always show.",
            groups: [
                { title: "Shown", rows: [{ kind: "cctiles", shown: true, label: "" }] },
                { title: "Not shown", rows: [{ kind: "cctiles", shown: false, label: "" }] },
                { title: "", rows: [
                    { kind: "action", label: "Default tiles", desc: "The tiles and the order it came with", button: "Reset", confirm: true,
                      run: () => Settings.reset("controlTiles") }
                ] },
                { title: "Hotspot", rows: [
                    { name: "hotspotName", kind: "text", label: "Network name", desc: "Empty: Hotspot-<this computer's name>. NetworkManager makes its password the first time and keeps it; the hotspot page shows it",
                      placeholder: "Hotspot-…" },
                    { kind: "action", label: "New password", desc: "Forgets the hotspot (NetworkManager's \"Hotspot\" profile): the next one gets a new password", button: "Forget", confirm: true,
                      run: () => Hotspot.forgetProfile(), status: () => Hotspot.on ? "Turn the hotspot off first" : Hotspot.error }
                ] },
                { title: "Name that song", rows: [
                    { name: "songSource", kind: "choice", label: "Listen to", desc: "Shazam gets a fingerprint of the sound (not the sound). A right click on the tile takes the other one",
                      choices: [{ value: "output", label: "What plays here" }, { value: "mic", label: "Microphone" }] },
                    { name: "songListenSeconds", kind: "number", label: "Give up after", desc: "Three tries in that time; the first after a third of it", from: 6, to: 30, step: 3, format: v => Math.round(v) + " s" }
                ] }
            ]
        },
        {
            id: "keyboard", title: "On-screen keyboard", icon: "keyboard",
            blurb: "Comes up when you fold the screen back into a tablet, or from the bar's keyboard item (Bar items). It types into the window you're in. Tablet: turning the screen, and the laptop's own keyboard when folded.",
            groups: [
                { title: "", rows: [
                    { name: "oskAutoTablet", kind: "bool", label: "Show in tablet mode", desc: "Up when the screen folds back, away when it folds again (mango's switchbind lines run `mine osk fold` / `unfold`)" },
                    { kind: "action", label: "Show it now", desc: "Or hide it again (its ⌨ key hides it too)", button: "Show / hide", run: () => OskState.toggle() }
                ] },
                { title: "Tablet", rows: [
                    { name: "rotateScreen", kind: "choice", label: "Turn the screen", desc: "Follows which way up you hold it. In tablet mode: only while folded back. Always: as a laptop too",
                      status: () => AutoRotate.summary,
                      choices: [{ value: "off", label: "Off" }, { value: "tablet", label: "In tablet mode" }, { value: "always", label: "Always" }] },
                    { kind: "bool", label: "Hold the screen as it is", desc: "Stops turning until switched off (also the control center's Auto-rotate tile); not kept after a restart", resets: [],
                      get: () => AutoRotate.locked, flip: () => AutoRotate.toggleLock() },
                    { name: "tabletKeepKeyboard", kind: "bool", label: "Keyboard and touchpad when folded", desc: "On: they keep working laid flat (the hardware may still cut them past about 180°). Off: libinput turns them off in tablet mode" },
                    { kind: "action", label: "Set it up", desc: "Needs sudo (the shell can't): copies the command for the switch above", button: "Copy command", run: () => TabletMode.copyKeyboardCommand(),
                      status: () => TabletMode.keyboardQuirk === "" ? ""
                          : !TabletMode.keyboardSetUp ? "To do: " + TabletMode.keyboardCommand + " in a terminal, then log out and in"
                          : TabletMode.keyboardQuirk === "on" ? "Done (/etc/libinput): counts from the first login after it was run"
                          : "Nothing to do (libinput's default)" }
                ] },
                { title: "Look", rows: [
                    { name: "oskHeight", kind: "number", label: "Height", desc: "Windows shrink above it", from: 200, to: 440, step: 10, format: root.px },
                    { name: "oskMaxWidth", kind: "number", label: "Width", desc: "At most; centered on wider screens", from: 600, to: 1600, step: 50, format: root.px },
                    { name: "oskKeyRadius", kind: "number", label: "Key corners", desc: "", from: 0, to: 24, step: 1, format: root.px },
                    { name: "oskOpacity", kind: "number", label: "Glass", desc: "", from: 0.2, to: 0.95, step: 0.05, format: root.percent }
                ] },
                { title: "Holding ⌫ or an arrow", rows: [
                    { name: "oskRepeatDelay", kind: "number", label: "Repeats after", desc: "", from: 200, to: 1000, step: 50, format: root.ms },
                    { name: "oskRepeatInterval", kind: "number", label: "Then every", desc: "", from: 30, to: 200, step: 10, format: root.ms }
                ] }
            ]
        },
        {
            id: "wallpaper", title: "Wallpaper", icon: "wallpaper",
            blurb: "All the shell's colors follow it.",
            groups: [
                { title: "", rows: [
                    { kind: "wallpaper", label: "Wallpaper", desc: "" },
                    { name: "wallpaperScheme", kind: "choice", label: "Color style", desc: "How the colors are taken from the picture",
                      choices: [{ value: "scheme-content", label: "Content" }, { value: "scheme-tonal-spot", label: "Tonal" }, { value: "scheme-vibrant", label: "Vibrant" }, { value: "scheme-expressive", label: "Expressive" }, { value: "scheme-neutral", label: "Neutral" }] },
                    { name: "wallpaperReveal", kind: "number", label: "Change animation", desc: "How long a new wallpaper takes to spread out", from: 0, to: 2000, step: 100, format: root.ms },
                    { name: "wallpaperDir", kind: "text", label: "Folder", desc: "Where the pictures are (subfolders too)", placeholder: "~/Pictures/Wallpapers" }
                ] },
                { title: "Slideshow", rows: [
                    { name: "wallpaperSlideshow", kind: "number", label: "New wallpaper", desc: "Colors follow; waits while the screen is dimmed or off", from: 0, to: 240, step: 5,
                      format: v => v <= 0 ? "Off" : v < 60 ? "Every " + Math.round(v) + " min" : "Every " + (v / 60).toFixed(1).replace(/\.0$/, "") + " h" },
                    { name: "wallpaperSlideshowOrder", kind: "choice", label: "Which one", desc: "",
                      choices: [{ value: "random", label: "Random" }, { value: "next", label: "Next in the folder" }] }
                ] },
                { title: "Picture of the day", rows: [
                    { name: "wallpaperDaily", kind: "choice", label: "New picture each day", desc: "Downloaded to the Daily folder (the last 14 kept); pick another and it stays until tomorrow's",
                      choices: [{ value: "off", label: "Off" }, { value: "bing", label: "Bing" }] }
                ] },
                { title: "While music plays", rows: [
                    { name: "artColors", kind: "bool", label: "Colors from the album cover", desc: "The shell's colors follow the song's cover, then the wallpaper's again",
                      status: () => ArtColors.active ? "Now showing the cover's colors" : "" },
                    { name: "artColorsStrength", kind: "choice", label: "What changes", desc: "Accents: buttons, sliders, highlights; everything: the glass too",
                      choices: [{ value: "accent", label: "Accents" }, { value: "full", label: "Everything" }] },
                    { name: "artColorsHold", kind: "number", label: "Back to the wallpaper", desc: "After the music stops or pauses", from: 0, to: 60, step: 1,
                      format: v => v <= 0 ? "Right away" : "After " + Math.round(v) + " s" }
                ] },
                { title: "Picker (Super+Y)", rows: [
                    { name: "pickerColumns", kind: "number", label: "Columns", desc: "", from: 2, to: 6, step: 1, format: root.count },
                    { name: "pickerRows", kind: "number", label: "Rows", desc: "Before it scrolls", from: 2, to: 5, step: 1, format: root.count },
                    { name: "pickerThumbWidth", kind: "number", label: "Picture size", desc: "", from: 120, to: 240, step: 8, format: root.px }
                ] }
            ]
        },
        {
            id: "desktop", title: "Desktop & night light", icon: "desktop_windows",
            blurb: "The clock on the wallpaper, and warmer colors at night.",
            groups: [
                { title: "Clock on the desktop", rows: [
                    { name: "desktopClock", kind: "bool", label: "Clock on the desktop", desc: "The time, the date and the weather, under your windows" },
                    { name: "desktopClockPosition", kind: "choice", label: "Where", desc: "",
                      choices: [{ value: "top-left", label: "Top left" }, { value: "top-right", label: "Top right" }, { value: "center", label: "Middle" }, { value: "bottom-left", label: "Bottom left" }, { value: "bottom-right", label: "Bottom right" }] },
                    { name: "desktopClockScale", kind: "number", label: "Size", desc: "", from: 0.5, to: 2, step: 0.05, format: root.times },
                    { name: "desktopClockShowWeather", kind: "bool", label: "Weather", desc: "From Calendar & weather" }
                ] },
                { title: "Widgets on the desktop", rows: [
                    root.widgetRow("music", "Music", "Cover, song, buttons and lyrics, while something plays"),
                    root.widgetRow("system", "System", "CPU, memory and temperature rings, network speed"),
                    root.widgetRow("calendar", "Calendar", "This month, and today's events if you set a calendar"),
                    { name: "desktopWidgetsSide", kind: "choice", label: "Where", desc: "Next to the clock, or above it (at the bottom; under it elsewhere)",
                      choices: [{ value: "auto", label: "Auto" }, { value: "beside", label: "Beside" }, { value: "stacked", label: "Stacked" }] },
                    { name: "desktopWidgetOpacity", kind: "number", label: "Glass", desc: "How solid the cards are", from: 0.3, to: 1, step: 0.05, format: root.percent },
                    { name: "desktopMusicTint", kind: "number", label: "Cover color in the music card", desc: "0 = plain glass", from: 0, to: 1, step: 0.05, format: root.percent }
                ] },
                { title: "Night light", rows: [
                    { name: "nightLightMode", kind: "choice", label: "Night light", desc: "Warmer colors, easier on the eyes in the evening",
                      status: () => NightLight.available ? "" : "Needs wlsunset: sudo pacman -S wlsunset",
                      choices: [{ value: "off", label: "Off" }, { value: "schedule", label: "At night" }, { value: "on", label: "Always" }] },
                    { name: "nightLightTemp", kind: "number", label: "Warmth", desc: "Lower is warmer; 6500 K is normal", from: 2500, to: 6000, step: 100, format: v => Math.round(v) + " K" },
                    { name: "nightLightUseLocation", kind: "bool", label: "Sunset to sunrise", desc: "At the weather place; off: the times below" },
                    { name: "nightLightFrom", kind: "text", label: "From", desc: "24-hour time", placeholder: "20:00",
                      status: () => NightLight.clockTime(Style.nightLightFrom, "") === "" ? "Not a time: use 24-hour time like 20:00" : "" },
                    { name: "nightLightTo", kind: "text", label: "Until", desc: "24-hour time", placeholder: "07:00",
                      status: () => NightLight.clockTime(Style.nightLightTo, "") === "" ? "Not a time: use 24-hour time like 07:00" : "" }
                ] }
            ]
        },
        {
            id: "screenshots", title: "Screenshots", icon: "screenshot_region",
            blurb: "Print or Super+Shift+S: drag a region or click a window. Ctrl+Print: the whole screen. Super+Shift+T: copy the text in a region.",
            rows: [
                { name: "screenshotDir", kind: "text", label: "Save to", desc: "Also copied to the clipboard", placeholder: "~/Pictures/Screenshots" },
                { name: "screenshotConfirm", kind: "bool", label: "Adjust before saving", desc: "Drag the region into place, then Enter" },
                { name: "screenshotNotify", kind: "bool", label: "Notification", desc: "With the picture: open, edit or delete it" },
                { name: "screenshotDim", kind: "number", label: "Darken outside the selection", desc: "", from: 0, to: 0.8, step: 0.05, format: root.percent },
                { name: "screenshotEditor", kind: "choice", label: "Edit with", desc: "Edit in the overlay (E) and the notification's Edit: draw on it right there, or open swappy after saving",
                  choices: [{ value: "markup", label: "Markup" }, { value: "swappy", label: "swappy" }] },
                { name: "screenshotPixelSize", kind: "number", label: "Blur blocks", desc: "How coarse the markup's blur is, in real pixels", from: 8, to: 32, step: 2, format: root.px },
                { name: "ocrLanguages", kind: "text", label: "Copy text: languages", desc: "Super+Shift+T reads the words in a region. auto = English, plus Vietnamese when tesseract-data-vie is installed", placeholder: "auto" },
                // Scan a QR code, Google Lens, Translate (the overlay's tools).
                { kind: "info", label: "In the overlay", text: () => "T copy text · Q scan a QR code · L Google Lens · D translate" },
                { name: "translatePair", kind: "text", label: "Translate: languages", desc: "Yours, then the other one: text in yours goes to the other, anything else to yours", placeholder: "vi:en",
                  status: () => {
                      const m = Style.translatePair.trim().match(/^([A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?)\s*[:>,/ ]\s*([A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?)$/);
                      return m && m[1].toLowerCase() !== m[2].toLowerCase() ? "" : "Two different language codes, like vi:en";
                  } },
                { kind: "info", label: "Translate with", text: () => "Google, over HTTPS: the text read off the screen is sent there" }
            ]
        },
        {
            id: "recording", title: "Recording & colors", icon: "screen_record",
            blurb: "Super+Shift+R records the screen, Super+Alt+R a region (or the Record tile); the red dot in the bar stops it. Super+Shift+C picks a color.",
            groups: [
                { title: "Screen recording", rows: [
                    { name: "recordDir", kind: "text", label: "Save to", desc: "As .mp4", placeholder: "~/Videos/Recordings" },
                    { name: "recordAudio", kind: "bool", label: "Sound", desc: "Also record what you hear (not the microphone)" },
                    { name: "recordHardware", kind: "bool", label: "Encode on the GPU", desc: "Lighter on the CPU, bigger files (VA-API)" },
                    { kind: "action", label: "Record now", desc: "The whole screen; click the red dot to stop", button: "Record",
                      run: () => { SettingsState.close(); Recorder.startSoon("screen"); } }
                ] },
                { title: "Color picker", rows: [
                    { kind: "action", label: "Pick a color", desc: "Click anywhere on the screen; the hex is copied", button: "Pick",
                      run: () => ColorPicker.pick() },
                    { kind: "info", label: "Last picked", text: () => ColorPicker.last || "Nothing yet" }
                ] }
            ]
        },
        {
            id: "power", title: "Power & locking", icon: "battery_charging_full",
            blurb: "Locking, what happens when you leave the laptop alone, auto brightness, and the keys.",
            groups: [
                { title: "", rows: [
                    { name: "lockBeforeSleep", kind: "bool", label: "Lock before sleep", desc: "When the lid closes or the laptop suspends" },
                    { name: "dimAfter", kind: "number", label: "Dim the screen after", desc: "Without keyboard or mouse", from: 0, to: 1800, step: 30, format: root.after },
                    { name: "idleDimLevel", kind: "number", label: "Dim to", desc: "Brightness while dimmed", from: 0.02, to: 0.5, step: 0.02, format: root.percent },
                    { name: "screenOffAfter", kind: "number", label: "Turn the screen off after", desc: "", from: 0, to: 3600, step: 30, format: root.after },
                    { name: "lockAfter", kind: "number", label: "Lock after", desc: "", from: 0, to: 3600, step: 60, format: root.after },
                    { name: "lockedScreenOffAfter", kind: "number", label: "Screen off on the lock screen after", desc: "Spares the OLED a still clock", from: 0, to: 600, step: 10, format: root.after },
                    { name: "suspendOnBatteryAfter", kind: "number", label: "Sleep on battery after", desc: "Not while music or a video plays", from: 0, to: 7200, step: 300, format: root.after }
                ] },
                { title: "Presence sensor", rows: [
                    { name: "presenceLock", kind: "bool", label: "Lock when you walk away", desc: "The camera's sensor, read only while you're idle; no dimming while you look",
                      status: () => !Presence.enabled ? "" : Presence.device !== "" ? Presence.device.split("/").pop() + " · " + Presence.reads + " reads"
                          : Presence.searched ? "No presence sensor found" : "" },
                    { name: "presenceIdle", kind: "number", label: "Start checking after", desc: "Without keyboard or mouse", from: 10, to: 300, step: 10, format: root.after },
                    { name: "presenceEvery", kind: "number", label: "Check every", desc: "Each check wakes the camera for ~2 s", from: 3, to: 15, step: 1, format: v => Math.round(v) + " s" },
                    { name: "presenceAwayFor", kind: "number", label: "Lock when nobody's there for", desc: "", from: 5, to: 60, step: 5, format: v => Math.round(v) + " s" },
                    { name: "presenceDimHold", kind: "number", label: "Keep bright while you look, at most", desc: "", from: 60, to: 3600, step: 60, format: root.after }
                ] },
                { title: "Auto brightness", rows: [
                    { name: "autoBrightness", kind: "bool", label: "Auto brightness", desc: "Follows the light around you (the light sensor), and learns from the changes you make yourself" },
                    { kind: "info", label: "Now", text: () => AutoBrightness.info },
                    { name: "autoBrightnessMin", kind: "number", label: "Never darker than", desc: "Unless you make it darker yourself (then that's learned)", from: 0.05, to: 0.6, step: 0.05, format: root.percent },
                    { name: "autoBrightnessMax", kind: "number", label: "Never brighter than", desc: "Unless you make it brighter yourself", from: 0.3, to: 1, step: 0.05, format: root.percent },
                    { name: "autoBrightnessGlide", kind: "number", label: "A change takes", desc: "A slow glide, not a jump", from: 1, to: 10, step: 1, format: v => Math.round(v) + " s" },
                    { name: "autoBrightnessHold", kind: "number", label: "After you change it, wait", desc: "Or until the light halves or doubles", from: 1, to: 60, step: 1, format: v => Math.round(v) + " min" },
                    { kind: "action", label: "Forget what it learned", desc: "Back to the usual curve", button: "Forget", confirm: true,
                      run: () => AutoBrightness.forget(), status: () => AutoBrightness.learnedText }
                ] },
                { title: "Battery", rows: [
                    { name: "batterySaverOnBattery", kind: "bool", label: "Power saver on battery", desc: "Unplugged: Power saver; plugged in: back to what it was" },
                    { name: "batteryWarnLow", kind: "number", label: "Low battery warning", desc: "A notification once per charge", from: 0, to: 40, step: 5, format: v => v <= 0 ? "Off" : Math.round(v) + "%" },
                    { name: "batteryWarnCritical", kind: "number", label: "Almost empty warning", desc: "Urgent, with sound, even when Silent", from: 0, to: 15, step: 1, format: v => v <= 0 ? "Off" : Math.round(v) + "%" },
                    { name: "batteryFullNotice", kind: "number", label: "Charged notice", desc: "While plugged in, e.g. 80% to spare the battery", from: 0, to: 100, step: 5, format: v => v <= 0 ? "Off" : Math.round(v) + "%" },
                    { name: "deviceBatteryWarn", kind: "number", label: "Headphones, mouse… low", desc: "Connected devices: a notification once; add \"Device batteries\" in Bar items to see them",
                      from: 0, to: 40, step: 5, format: v => v <= 0 ? "Off" : Math.round(v) + "%",
                      status: () => Peripherals.devices.length === 0 ? "" : Peripherals.devices.map(d => d.name + " " + d.percent + "%").join(" · ") }
                ] },
                { title: "Keys", rows: [
                    { name: "keyVolumeStep", kind: "number", label: "Volume key step", desc: "", from: 0.01, to: 0.1, step: 0.01, format: root.percent },
                    { name: "keyBrightnessStep", kind: "number", label: "Brightness key step", desc: "", from: 0.01, to: 0.2, step: 0.01, format: root.percent }
                ] },
                // Battery popup (services/BatteryHealth.qml, control/BatteryPopup.qml).
                { title: "Battery popup", rows: [
                    { kind: "info", label: "Health", text: () => !BatteryHealth.healthKnown ? "Checking…"
                        : !BatteryHealth.hasHealth ? "The battery doesn't report it"
                        : BatteryHealth.condition + " · holds " + BatteryHealth.healthText + " of new (" + BatteryHealth.fullText + " of " + BatteryHealth.designText + ")"
                          + (BatteryHealth.cycles > 0 ? " · " + BatteryHealth.cycles + " cycles" : "") },
                    { name: "batteryPopup", kind: "bool", label: "Click the battery for its popup", desc: "The charge over the last hours and the battery's health. Off: the click opens the control center (right click always does)" },
                    { name: "batteryGraphHours", kind: "number", label: "Graph goes back", desc: "UPower's own history of the charge", from: 6, to: 72, step: 6, format: v => Math.round(v) + " h" },
                    { name: "batteryPopupWidth", kind: "number", label: "Width", desc: "", from: 280, to: 440, step: 10, format: root.px }
                ] }
            ]
        },
        {
            id: "lock", title: "Lock screen", icon: "lock",
            blurb: "Super+Alt+L, closing the lid, or when you're away. Simple: the time big, you and the password at the bottom, like a Mac. Panel: the bar's glass around cards.",
            groups: [
                { title: "Style", rows: [
                    { name: "lockStyle", kind: "choice", label: "Style", desc: "",
                      choices: [{ value: "mac", label: "Simple (Mac)" }, { value: "panel", label: "Panel" }] },
                    { name: "lockHideAfter", kind: "number", label: "Only the time after", desc: "Simple style: without keyboard or mouse; any key brings the rest back",
                      from: 0, to: 120, step: 5, format: root.after },
                    { name: "lockClockFont", kind: "text", label: "Time font", desc: "Simple style; empty = SF Pro Rounded if installed, else the bar's font",
                      placeholder: "SF Pro Rounded" },
                    { name: "lockFieldContrast", kind: "choice", label: "On a bright wallpaper", desc: "Simple style and the login screen: Auto darkens the field, the pills and the words' shadows only as much as a bright picture behind them needs",
                      choices: [{ value: "auto", label: "Auto" }, { value: "light", label: "See-through" }, { value: "dark", label: "Always darker" }] },
                    { name: "lockContrastFrom", kind: "number", label: "Help starts at", desc: "Auto: how bright the picture behind must be before anything changes", from: 0.2, to: 0.8, step: 0.05, format: root.percent },
                    { name: "lockContrastTo", kind: "number", label: "Full help at", desc: "Auto: how bright it is when the darker look is at its strongest", from: 0.4, to: 1, step: 0.05, format: root.percent }
                ] },
                { title: "What it shows", rows: [
                    { name: "lockShowMedia", kind: "bool", label: "Now playing", desc: "The song or video playing, with its buttons, in both styles. Off: anyone at the laptop can't see what you listen to or watch" }
                ] },
                { title: "Unlock", rows: [
                    { name: "lockFace", kind: "bool", label: "Unlock with your face", desc: "The IR camera, like Windows Hello: it looks once you move the mouse or type on the lock (not the moment it locks), when you come back to it, or when you click your picture. The password always works too" }
                ] },
                { title: "Behind", rows: [
                    { name: "lockWallpaperBlur", kind: "number", label: "Wallpaper blur", desc: "Panel style (the simple one shows the wallpaper sharp)", from: 0, to: 1, step: 0.05, format: root.percent }
                ] },
                { title: "Panel style", rows: [
                    { name: "lockOpacity", kind: "number", label: "Glass", desc: "How tinted the panel and the islands are", from: 0.2, to: 0.95, step: 0.05, format: root.percent },
                    { name: "lockRadius", kind: "number", label: "Corners", desc: "", from: 12, to: 56, step: 2, format: root.px },
                    { name: "lockWeatherTempSize", kind: "number", label: "Weather temperature", desc: "On the weather card", from: 18, to: 44, step: 2, format: root.px }
                ] },
                { title: "Panel style: cards", rows: [
                    { name: "lockShowWeather", kind: "bool", label: "Weather", desc: "From the Calendar & weather place" },
                    { name: "lockShowFetch", kind: "bool", label: "System info", desc: "user@host, kernel, uptime, packages" },
                    { name: "lockShowResources", kind: "bool", label: "Gauges", desc: "CPU, memory, temperature, battery" },
                    { name: "lockShowCalendar", kind: "bool", label: "Calendar", desc: "This month" }
                ] },
                { title: "", rows: [
                    { kind: "action", label: "Lock now", desc: "See it for real", button: "Lock",
                      run: () => Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/qs-lock"]) }
                ] }
            ]
        },
        {
            id: "calendar", title: "Calendar & weather", icon: "calendar_month",
            blurb: "Click the clock: the middle island grows into a calendar with your events and the weather.",
            groups: [
                { title: "Weather", rows: [
                    { name: "weatherEnabled", kind: "bool", label: "Weather", desc: "From Open-Meteo, no account needed" },
                    { name: "weatherCity", kind: "text", label: "Place", desc: "Type a city and press Enter",
                      placeholder: "City", commit: t => Weather.findPlace(t), status: () => Weather.placeStatus,
                      resets: ["weatherCity", "weatherLatitude", "weatherLongitude"] },
                    { name: "weatherHours", kind: "number", label: "Hours ahead", desc: "", from: 3, to: 8, step: 1, format: root.count },
                    { name: "weatherRefreshMinutes", kind: "number", label: "Update every", desc: "", from: 10, to: 120, step: 10, format: v => Math.round(v) + " min" }
                ] },
                { title: "Your events", rows: [
                    { name: "calendarIcsUrls", kind: "text", label: "Calendars",
                      desc: "Google Calendar → ⚙ Settings → your calendar → \"Secret address in iCal format\". Several: spaces between. Keep it private",
                      placeholder: "https://calendar.google.com/…/basic.ics", secret: true, status: () => Events.status },
                    { name: "calendarRefreshMinutes", kind: "number", label: "Update every", desc: "", from: 5, to: 120, step: 5, format: v => Math.round(v) + " min" },
                    { name: "clockNextEvent", kind: "bool", label: "Next event on the bar", desc: "Next to the clock, from an hour before" }
                ] },
                { title: "Calendar", rows: [
                    { name: "calendarWidth", kind: "number", label: "Width", desc: "", from: 320, to: 480, step: 10, format: root.px },
                    { name: "calendarRadius", kind: "number", label: "Corners", desc: "", from: 12, to: 40, step: 1, format: root.px },
                    { name: "calendarDaySize", kind: "number", label: "Day number", desc: "Today's big number", from: 24, to: 56, step: 2, format: root.px }
                ] }
            ]
        },
        // Screen time, break reminders, AI usage (services/ScreenTime.qml,
        // services/Breaks.qml, services/AiUsage.qml).
        {
            id: "usage", title: "Screen time", icon: "hourglass_bottom",
            blurb: "Time on the screen per app, reminders to take a break, and your Claude and Codex limits. \"Screen time\" and \"AI usage\" are in Bar items.",
            groups: [
                { title: "Screen time", rows: [
                    { name: "screenTime", kind: "bool", label: "Count screen time", desc: "The focused app, while the screen is on, not locked and you're there; kept on this computer only",
                      status: () => !Style.screenTime ? "" : "Today " + ScreenTime.durationText(ScreenTime.totalOn(ScreenTime.today, Date.now() + ScreenTime.revision * 0), false)
                          + (ScreenTime.current !== "" ? " · now " + ScreenTime.appName(ScreenTime.current) : "") },
                    { name: "screenTimeIdle", kind: "number", label: "Stops after no input for", desc: "Counted up to your last input; a fullscreen window or a playing video goes on",
                      from: 60, to: 900, step: 30, format: root.after },
                    { name: "screenTimeDays", kind: "number", label: "Keep", desc: "", from: 7, to: 90, step: 1, format: v => Math.round(v) + " days" },
                    { name: "screenTimePopupWidth", kind: "number", label: "Popup width", desc: "", from: 300, to: 440, step: 10, format: root.px }
                ] },
                { title: "Break reminders", rows: [
                    { name: "breakReminders", kind: "bool", label: "Remind me to take a break", desc: "A notification with Snooze and Take a break; not while fullscreen, sharing the screen or Silent",
                      status: () => Breaks.detail },
                    { name: "breakAfter", kind: "number", label: "After", desc: "On the screen without a real break", from: 20, to: 120, step: 5, format: v => Math.round(v) + " min" },
                    { name: "breakResetAfter", kind: "number", label: "A real break is", desc: "Away this long (no input, locked, asleep): the clock starts over", from: 2, to: 20, step: 1, format: v => Math.round(v) + " min" },
                    { name: "breakSnooze", kind: "number", label: "Snooze", desc: "", from: 5, to: 30, step: 5, format: v => Math.round(v) + " min" },
                    { name: "breakLength", kind: "number", label: "Take a break: countdown", desc: "The screen dims with a countdown; Skip or Esc ends it", from: 1, to: 15, step: 1, format: v => Math.round(v) + " min" },
                    { name: "breakDim", kind: "number", label: "Darken during the break", desc: "", from: 0, to: 0.8, step: 0.05, format: root.percent },
                    { name: "breakEyes", kind: "bool", label: "20-20-20 eye reminder", desc: "Every few minutes on the screen: look 20 seconds at something 6 m away" },
                    { name: "breakEyesEvery", kind: "number", label: "Eye reminder every", desc: "", from: 10, to: 60, step: 5, format: v => Math.round(v) + " min" }
                ] },
                { title: "AI usage", rows: [
                    { kind: "info", label: "Signed in", text: () => [AiUsage.claude.present ? "Claude" + (AiUsage.claude.phase === "expired" ? " (sign-in expired)" : "") : "",
                                                                      AiUsage.codex.present ? "Codex" + (AiUsage.codex.phase === "expired" ? " (sign-in expired)" : "") : ""]
                          .filter(t => t !== "").join(" · ") || "Neither Claude Code nor Codex" },
                    { name: "aiUsagePoll", kind: "number", label: "Check every", desc: "Only while \"AI usage\" is on the bar or its popup is open", from: 1, to: 30, step: 1, format: v => Math.round(v) + " min" },
                    { name: "aiUsageNotify", kind: "bool", label: "Notify when a limit gets close", desc: "Once per window at each of the two levels below" },
                    { name: "aiUsageWarnAt", kind: "number", label: "Getting close at", desc: "Orange ring (unless the service says otherwise)", from: 50, to: 95, step: 5, format: v => Math.round(v) + "%" },
                    { name: "aiUsageCriticalAt", kind: "number", label: "Nearly out at", desc: "Red ring", from: 80, to: 100, step: 1, format: v => Math.round(v) + "%" },
                    { name: "aiUsageWarnColor", kind: "text", label: "Getting close: color", desc: "#RRGGBB or a name; nearly out uses the error color", placeholder: "#ff9f0a",
                      commit: t => root.setColor("aiUsageWarnColor", t) },
                    { name: "aiUsagePopupWidth", kind: "number", label: "Popup width", desc: "", from: 300, to: 440, step: 10, format: root.px }
                ] }
            ]
        },
        // ---- Drawing on the screen, notes, timers ----------------------------------------
        {
            id: "desk", title: "Notes, drawing & timers", icon: "edit_note",
            blurb: "Draw on the screen with the pen, notes and to-dos (with the pen or the on-screen keyboard), and a timer, a stopwatch and alarms. Each has a control center tile (Edit there to add it).",
            groups: [
                // Timer, stopwatch, alarms (services/Timers.qml).
                { title: "Timer and alarms", rows: [
                    { name: "timersSnoozeMinutes", kind: "number", label: "Snooze", desc: "An alarm's Snooze button", from: 1, to: 30, step: 1, format: v => Math.round(v) + " min" },
                    { name: "timersRingSeconds", kind: "number", label: "Rings for", desc: "Then the sound stops by itself; the notification stays", from: 10, to: 300, step: 10, format: root.after },
                    { name: "timersRingInSilent", kind: "bool", label: "Ring in Silent", desc: "A timer or an alarm rings and pops up even while notifications are muted" },
                    { name: "timersVolume", kind: "number", label: "Volume", desc: "Of the alarm sound, under the system volume", from: 0.1, to: 1, step: 0.05, format: root.percent },
                    { kind: "info", label: "While the laptop sleeps", text: () => "Nothing rings: the shell can't wake it. A timer or an alarm whose time came then says it was missed when you're back." }
                ] },
                // Drawing on the screen (services/Ink.qml).
                { title: "Draw on the screen", rows: [
                    { kind: "info", label: "How", text: () => "The \"Draw on screen\" tile, or: qs -c mine ipc call ink toggle. Esc or × ends it (the ink goes too); the arrow button lets you use the apps with the ink still on screen" },
                    { name: "inkTouch", kind: "bool", label: "Draw with a finger too", desc: "Off: only the pen and the mouse draw, so a palm resting on the screen doesn't" },
                    { name: "inkFadeSeconds", kind: "number", label: "Strokes fade after", desc: "For pointing things out: each stroke goes by itself", from: 0, to: 30, step: 1,
                      format: v => v <= 0 ? "Never" : Math.round(v) + " s" },
                    { name: "inkToolbarOpacity", kind: "number", label: "Toolbar glass", desc: "", from: 0.5, to: 1, step: 0.05, format: root.percent }
                ] },
                // Notes and to-dos (services/Notes.qml).
                { title: "Notes", rows: [
                    root.widgetRow("notes", "Note on the desktop", "The pinned note (or the newest): tick items right there, click to open it"),
                    { name: "notesCollapseDone", kind: "bool", label: "Fold away done items", desc: "A checklist's ticked items go under \"N done\"" },
                    { name: "notesWidth", kind: "number", label: "Panel width", desc: "", from: 340, to: 560, step: 10, format: root.px },
                    { name: "notesHeight", kind: "number", label: "Panel height", desc: "At most; less above the on-screen keyboard", from: 400, to: 900, step: 20, format: root.px },
                    { name: "notesOpacity", kind: "number", label: "Panel glass", desc: "", from: 0.5, to: 0.98, step: 0.02, format: root.percent }
                ] }
            ]
        },
        {
            id: "about", title: "About", icon: "info",
            blurb: "Everything here is also in Style.qml, with a comment for each knob.",
            rows: [
                { kind: "info", label: "Quickshell", text: () => root.quickshell },
                { kind: "info", label: "Shell folder", text: () => Quickshell.shellDir },
                { kind: "info", label: "Your changes", text: () => Settings.path },
                { kind: "action", label: "Style.qml", desc: "Every knob, with comments (opens in micro)", button: "Edit", run: () => Panels.editStyle() },
                { kind: "action", label: "Reset everything", desc: "Every setting back to Style.qml", button: "Reset all", confirm: true, run: () => Settings.resetAll() }
            ]
        }
    ]
}
