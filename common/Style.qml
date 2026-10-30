pragma Singleton
import QtQuick
import Quickshell

// Every size, opacity, font and knob of the shell in one place.
// Change a number and save: the running shell reloads by itself (the
// islands drop in again, so you see the change right away).
// Colors come from the wallpaper (Colors.qml); this file only says how
// strong they are.
//
// The Settings window (Super+, / ⚙) changes knobs without touching this
// file: what you change there is kept in ~/.local/state/mine-shell/
// settings.json and wins over the number here; "Reset" goes back to it.
// Every knob reads its override first, one line each:
//     readonly property int dockIconSize: Settings.values.dockIconSize ?? 40
// A new knob becomes settable the same way: `Settings.values.<name> ?? <default>`
// (and a row in settings/Sections.qml to show it in the window).
Singleton {
    // ---- Islands: the three floating glass pills --------------------------------
    // (In one bar, Style.barStyle, the islands are the bar's height minus
    // its padding: barHeight - 2 * barPad.)
    readonly property int islandHeight: barJoined ? barHeight - 2 * barPad : Settings.values.islandHeight ?? 36
    readonly property int marginEdge: Settings.values.marginEdge ?? 6    // gap between the screen top and the islands
    readonly property int marginEnds: Settings.values.marginEnds ?? 8    // gap at the left and right screen edges
    readonly property int islandRadius: Settings.values.islandRadius ?? 18    // islandHeight / 2 = full pill
    readonly property real islandOpacity: Settings.values.islandOpacity ?? 0.55    // glass tint; mango blurs what's behind it
    readonly property color islandBorder: Settings.values.islandBorder ?? "#1fffffff"    // QML colors are #AARRGGBB (alpha first)
    readonly property real islandBorderWidth: Settings.values.islandBorderWidth ?? 1
    readonly property real islandSheen: Settings.values.islandSheen ?? 0.07    // soft light on the top half, 0 = off
    // "liquid": light on the glass edge itself (common/Glass.qml), a rim bright
    // where the edge faces the light, a faint glint on the far side, a glow
    // just inside the lit edge and a little shade inside the bottom one, all
    // inside the pane. "flat": the plain tint and edge line only.
    readonly property string glassStyle: Settings.values.glassStyle ?? "liquid"
    // "expressive": Material 3's shapes behind icons (cookies, clovers,
    // bursts), morphing with state. "simple": circles everywhere (the bar's
    // launcher keeps its own).
    readonly property string shapeStyle: Settings.values.shapeStyle ?? "expressive"
    // Control center tiles. "filled": an on tile fills with the accent.
    // "calm": tiles stay neutral, only the icon's circle turns accent.
    readonly property string tileStyle: Settings.values.tileStyle ?? "filled"
    readonly property color glassBorder: Settings.values.glassBorder ?? "#12ffffff"    // the even edge line under the rim (liquid only; flat uses islandBorder)
    readonly property real glassLightAngle: Settings.values.glassLightAngle ?? 25    // degrees the light sits left of straight above (negative = right)
    readonly property real glassRim: Settings.values.glassRim ?? 0.75    // the rim facing the light
    readonly property real glassRimBack: Settings.values.glassRimBack ?? 0.35    // the glint on the far (bottom) side
    readonly property real glassRimWidth: Settings.values.glassRimWidth ?? 1.6    // px
    readonly property real glassGlow: Settings.values.glassGlow ?? 0.14    // glow just inside the lit edge
    readonly property int glassGlowDepth: Settings.values.glassGlowDepth ?? 14    // px it reaches in
    readonly property real glassShade: Settings.values.glassShade ?? 0.2    // shade inside the bottom edge
    readonly property int glassShadeDepth: Settings.values.glassShadeDepth ?? 8    // px it reaches in
    readonly property real glassEdge: Settings.values.glassEdge ?? 0.08    // light band all around, just inside the edge
    readonly property int glassEdgeDepth: Settings.values.glassEdgeDepth ?? 5    // px it reaches in
    readonly property int islandPadding: Settings.values.islandPadding ?? 4    // island edge -> first/last thing inside
    readonly property int islandSpacing: Settings.values.islandSpacing ?? 2    // between things inside an island
    readonly property int dropInDelay: Settings.values.dropInDelay ?? 70    // ms between islands dropping in at start
    readonly property bool startupIntro: Settings.values.startupIntro ?? true    // at start: the wallpaper fades in, then the bar, dock and desktop come in (common/Intro.qml)

    // ---- Bar style -------------------------------------------------------------------
    // "islands": the three pills float apart. The others put them in one bar
    // across the screen, as groups: "float" a rounded bar inside the gaps,
    // "hug" against the top edge and curving into the screen at both ends,
    // "plain" a flat strip.
    readonly property string barStyle: Settings.values.barStyle ?? "islands"
    readonly property bool barJoined: barStyle === "float" || barStyle === "hug" || barStyle === "plain"
    readonly property int barHeight: Settings.values.barHeight ?? 34    // one bar: how tall it is
    readonly property int barPad: Settings.values.barPad ?? 3    // one bar: its edge -> the groups inside
    readonly property real barOpacity: Settings.values.barOpacity ?? 0.62    // one bar: its glass tint
    readonly property bool barIslandDark: Settings.values.barIslandDark ?? true    // one bar: the middle island near-black, like a dynamic island (off: glass)
    readonly property real barIslandOpacity: Settings.values.barIslandOpacity ?? 0.92    // how solid that dark island is
    readonly property bool barIslandCards: Settings.values.barIslandCards ?? true    // what grows out of the dark island (notifications, launcher, calendar, player...) stays dark
    readonly property real barIslandCardOpacity: Settings.values.barIslandCardOpacity ?? 0.88    // how solid those cards are
    readonly property bool barCenterIsland: Settings.values.barCenterIsland ?? true    // one bar: the middle island keeps its own glass
    readonly property bool barGroups: Settings.values.barGroups ?? false    // one bar: a soft pill behind the side groups (off: they sit on the bar)
    readonly property real barGroupTint: Settings.values.barGroupTint ?? 0.07    // how light that pill is
    // Where the islands (or groups) really are, and where the bar ends: what
    // grows out of an island starts here, what opens under the bar goes
    // below barBottom. With "islands" these are marginEdge, marginEnds and
    // marginEdge + islandHeight, as always.
    readonly property int islandTop: barStyle === "float" ? marginEdge + barPad : barJoined ? barPad : marginEdge
    readonly property int islandSide: barStyle === "float" ? marginEnds + barPad : marginEnds
    readonly property int barBottom: islandTop + islandHeight + (barJoined ? barPad : 0)

    // ---- Corners ------------------------------------------------------------------
    // One scale for the whole shell. Something inside a rounded box, `gap` px
    // from its edge, gets the box's radius minus that gap (inner()), so both
    // curves share a center: nested corners run parallel instead of looking
    // pinched (inner too round) or puffy (inner too square). The islands are
    // already like that: a 28 px hover circle 4 px inside an 18 px pill.
    readonly property int radiusPanel: Settings.values.radiusPanel ?? 28    // panels that grow out of the bar: launcher, clipboard, control center, calendar, System, notifications, Alt+Tab
    readonly property int radiusPopup: Settings.values.radiusPopup ?? 20    // small popups: the volume popup
    readonly property int radiusDialog: Settings.values.radiusDialog ?? 34    // cards in the middle of the screen: power menu, password, shortcuts
    function inner(outer, gap) {
        return Math.max(6, outer - gap);
    }

    // ---- Things inside the islands ----------------------------------------------
    readonly property int itemHeight: Math.min(Settings.values.itemHeight ?? 28, islandHeight - 2)    // hover circles, workspace pill area
    readonly property real hoverTint: Settings.values.hoverTint ?? 0.08    // how much a button lights up on hover
    readonly property real pressTint: Settings.values.pressTint ?? 0.14
    readonly property real pressScale: Settings.values.pressScale ?? 0.9    // click squish
    // Tips under the bar's items (common/Tooltips.qml): what it is, its
    // state in words, its keys. The first one waits tooltipDelay; sliding
    // along the bar, the next ones come at once.
    readonly property bool tooltipsEnabled: Settings.values.tooltipsEnabled ?? true
    readonly property int tooltipDelay: Settings.values.tooltipDelay ?? 500    // ms
    readonly property int tooltipGap: Settings.values.tooltipGap ?? 6    // px between the island and the tip
    readonly property real tooltipOpacity: Settings.values.tooltipOpacity ?? 0.86    // glass of the tip (text must read well)
    // Icons that show a state are outlined while it's off and fill in when
    // it's on (Material Symbols' FILL axis): control center tiles, the
    // bar's speaker, phone and keyboard, list rows. Off: every icon filled.
    readonly property bool iconFillStates: Settings.values.iconFillStates ?? true

    // ---- Text and icons -----------------------------------------------------------
    readonly property string font: Settings.values.font ?? "Google Sans Flex"
    readonly property int fontSize: Settings.values.fontSize ?? 13
    readonly property int fontWeight: Settings.values.fontWeight ?? 500
    readonly property string iconFont: Settings.values.iconFont ?? "Material Symbols Rounded"
    readonly property int iconSize: Settings.values.iconSize ?? 18

    // ---- App icons ------------------------------------------------------------------
    // Every app icon (launcher, dock, workspaces, the window title, Alt+Tab,
    // notifications, the System popup, sound, overview, lock) sits on the same
    // tile: a squircle in glass tinted from the wallpaper (common/AppIcon.qml).
    // An icon that can't be found shows the app's first letter instead of
    // Qt's magenta "missing" square, in either style.
    readonly property string appIconStyle: Settings.values.appIconStyle ?? "tile"    // "tile" or "plain"
    readonly property real appIconTileOpacity: Settings.values.appIconTileOpacity ?? 0.85    // how solid the tile is
    readonly property real appIconInner: Settings.values.appIconInner ?? 0.72    // how much of the tile the icon fills
    readonly property real appIconRim: Settings.values.appIconRim ?? 0.2    // light along the tile's top edge, 0 = none

    // ---- Type scale ---------------------------------------------------------------
    // Text picks a role instead of its own pixel size, so every panel reads in
    // the same few steps: StyledText { role: "caption" }. A role is a size and
    // a weight (an explicit `weight:` still wins). textScale makes all of the
    // shell's text bigger or smaller at once. Big one-off numbers (the clocks)
    // keep their own knobs.
    readonly property real textScale: Settings.values.textScale ?? 1
    readonly property var textRoles: ({
        micro:    { size: 10, weight: 650 },    // badges, tiny counts
        caption:  { size: 11, weight: 500 },    // second lines, hints, times
        label:    { size: 12, weight: 600 },    // chips, small labels, row subtitles
        body:     { size: fontSize, weight: fontWeight },    // the default
        title:    { size: 15, weight: 650 },    // row, tile and card titles
        headline: { size: 19, weight: 700 },    // panel headings
        display:  { size: 24, weight: 700 }     // big values: temperatures, percentages
    })
    function textSize(role) {
        return Math.round((textRoles[role] ?? textRoles.body).size * textScale);
    }
    function textWeight(role) {
        return (textRoles[role] ?? textRoles.body).weight;
    }

    // ---- Widgets ------------------------------------------------------------------
    readonly property int workspacesShown: Settings.values.workspacesShown ?? 5    // at least this many workspace slots
    readonly property int workspaceSlot: Settings.values.workspaceSlot ?? 24    // size of one workspace slot
    readonly property bool workspaceIcons: Settings.values.workspaceIcons ?? true    // app icons in taken workspace slots (instead of the number)
    readonly property string workspaceStyle: Settings.values.workspaceStyle ?? "slots"    // "slots" (numbers or app icons) | "dots" (a dot each, the current one a long accent pill)
    readonly property int workspaceIconsMax: Settings.values.workspaceIconsMax ?? 3    // icons per slot, then "+n"
    readonly property int titleMaxWidth: Settings.values.titleMaxWidth ?? 300    // window title, before "..."
    readonly property int mediaMaxWidth: Settings.values.mediaMaxWidth ?? 200    // song title, before "..."
    readonly property bool showVisualizer: Settings.values.showVisualizer ?? true    // bars dancing next to the song (cava)
    readonly property int visualizerBars: Settings.values.visualizerBars ?? 6
    readonly property int visualizerFps: Settings.values.visualizerFps ?? 20    // times a second the bars move; the bar draws again each time (30 = smoother, more CPU)
    readonly property real volumeStep: Settings.values.volumeStep ?? 0.05    // per scroll step (5%)
    readonly property int batteryLow: Settings.values.batteryLow ?? 20    // % where the battery turns red
    readonly property int clockSize: Settings.values.clockSize ?? 15    // the time in the middle island
    readonly property string clockDate: Settings.values.clockDate ?? "ddd d MMM"    // Qt date format
    readonly property string clockLocale: Settings.values.clockLocale ?? "en_US"    // "" = system language (Vietnamese)
    readonly property bool clock24h: Settings.values.clock24h ?? true    // false: 12-hour with AM/PM

    // ---- Bar items: what each island holds, left to right ----------------------------
    // launcher workspaces layout window clock media tray network bluetooth
    // volume battery notifications controls power divider recording (the
    // red dot while the screen is recorded), updates (how many packages
    // wait, while some do), and the system stats cpu
    // memory temperature netspeed disk. Settings → Bar items moves
    // them around (or edit the lists here).
    readonly property var barLeft: Settings.values.barLeft ?? ["launcher", "workspaces", "layout", "window"]
    readonly property var barCenter: Settings.values.barCenter ?? ["clock", "media"]
    readonly property var barRight: Settings.values.barRight ?? ["recording", "tray", "updates", "network", "bluetooth", "volume", "battery", "divider", "notifications", "controls", "power"]
    // Items that have nothing to say step aside: the phone while it isn't
    // connected, the on-screen keyboard button outside tablet mode (or while
    // the keyboard isn't up). They slide back in when they're needed.
    readonly property bool barHideUnused: Settings.values.barHideUnused ?? true

    // ---- Updates (the bar's "updates" item) ---------------------------------------------
    // How many package updates wait (repos via checkupdates, the AUR via paru,
    // Flatpak); hidden while there are none. Click: the updates panel (the
    // lists, Arch news, Update installs the repo packages and Flatpaks right
    // there; "In terminal" runs the update command), or with updatesClick
    // "terminal" the update command in a terminal as before; right-click:
    // check now. Only checked while the item is on the bar.
    readonly property int updatesInterval: Settings.values.updatesInterval ?? 3    // hours between checks; 0 = never on its own
    readonly property int updatesFirstDelay: Settings.values.updatesFirstDelay ?? 5    // minutes after login before the first check
    readonly property int updatesRetry: Settings.values.updatesRetry ?? 30    // minutes before trying again when a check failed
    readonly property string updatesCommand: Settings.values.updatesCommand ?? "paru"    // shell text run in the terminal ("paru" = paru -Syu)
    readonly property string updatesClick: Settings.values.updatesClick ?? "panel"    // left-click: "panel" or "terminal" (the update command, as before)
    readonly property bool updatesNews: Settings.values.updatesNews ?? true    // the panel lists Arch news newer than your last full upgrade (the feed is read at most every 3 h)
    readonly property int updatesPanelWidth: Settings.values.updatesPanelWidth ?? 360
    readonly property bool updatesFlatpak: Settings.values.updatesFlatpak ?? true    // count Flatpak updates too (and run `flatpak update` after the command)
    // Named in the tip when they're among the updates (globs): things this
    // setup leans on (Quickshell's quirks, the pinned kernel and firmware,
    // the speaker fix's hand-placed UCM file).
    // The panel's Update asks again, listing them, when any of them is there.
    readonly property var updatesHeadsUp: Settings.values.updatesHeadsUp ?? ["quickshell*", "mango*", "linux", "linux-*", "mesa", "vulkan-radeon", "*firmware*", "amd-ucode", "alsa-ucm-conf", "pipewire*", "wireplumber", "qt6-base", "qt6-declarative", "qt6-wayland"]

    // ---- System stats on the bar ---------------------------------------------------------
    // Only read while one is on the bar. Click one: the System popup.
    readonly property int statsInterval: Settings.values.statsInterval ?? 2000    // ms between reads
    readonly property string statsMemoryAs: Settings.values.statsMemoryAs ?? "percent"    // "percent" or "gb"
    readonly property int statsWarnCpu: Settings.values.statsWarnCpu ?? 85    // % where the number turns red
    readonly property int statsWarnMemory: Settings.values.statsWarnMemory ?? 90    // %
    readonly property int statsWarnTemp: Settings.values.statsWarnTemp ?? 85    // °C
    readonly property int statsWarnDisk: Settings.values.statsWarnDisk ?? 90    // %
    readonly property string statsClickCommand: Settings.values.statsClickCommand ?? ""    // the popup's "Open btop" button; "" = btop in the terminal (or htop, Resources...)

    // ---- The System popup (click a stat on the bar) ------------------------------------
    // Grows out of the island the stat is on: rings for CPU, RAM, temperature
    // and disk, the CPU's recent graph, the busiest apps and the network.
    // Read only while it's open.
    readonly property int sysmonInterval: Settings.values.sysmonInterval ?? 1000    // ms between reads while open (processes: twice that)
    readonly property int sysmonProcessCount: Settings.values.sysmonProcessCount ?? 5
    readonly property string sysmonSortBy: Settings.values.sysmonSortBy ?? "cpu"    // "cpu" or "memory": how the processes start sorted
    readonly property int sysmonWidth: Settings.values.sysmonWidth ?? 380
    readonly property int sysmonRadius: Settings.values.sysmonRadius ?? radiusPanel
    readonly property real sysmonOpacity: Settings.values.sysmonOpacity ?? 0.84    // glass of the open popup

    // ---- Now Playing card ---------------------------------------------------------
    // Click the song in the middle island: the island grows into a player
    // (cover, seek bar, ⏮ ⏯ ⏭, the bars dancing, other players, volume), in
    // glass tinted from the cover. A click on the little cover (or a middle
    // click on the song) still just plays or pauses.
    //   qs -c mine ipc call nowplaying toggle
    readonly property bool nowPlayingEnabled: Settings.values.nowPlayingEnabled ?? true    // off: clicking the song plays/pauses, as before
    readonly property int nowPlayingWidth: Settings.values.nowPlayingWidth ?? 420
    readonly property int nowPlayingArtSize: Settings.values.nowPlayingArtSize ?? 104    // the cover, px
    readonly property real nowPlayingTint: Settings.values.nowPlayingTint ?? 0.35    // how much of the cover's color goes into the glass, 0 = none
    readonly property real nowPlayingOpacity: Settings.values.nowPlayingOpacity ?? 0.84    // glass of the open card
    readonly property int nowPlayingRadius: Settings.values.nowPlayingRadius ?? radiusPanel
    readonly property int nowPlayingSeekStep: Settings.values.nowPlayingSeekStep ?? 5    // s per ←/→ press

    // ---- Lyrics (services/Lyrics.qml, from lrclib.net) ----
    readonly property bool lyricsEnabled: Settings.values.lyricsEnabled ?? true    // off: never looked up, nothing shown
    readonly property bool lyricsInCard: Settings.values.lyricsInCard ?? true    // under the song in the Now Playing card (its lyrics button)
    readonly property bool lyricsInBar: Settings.values.lyricsInBar ?? true    // the line being sung in place of the song's name (timed lyrics only)
    readonly property bool lyricsOnDesktop: Settings.values.lyricsOnDesktop ?? true    // the song's lines gliding by in the desktop's music card (timed lyrics only)
    readonly property int lyricsDesktopHeight: Settings.values.lyricsDesktopHeight ?? 150    // the desktop card's lyrics, px
    readonly property real lyricsDesktopBlur: Settings.values.lyricsDesktopBlur ?? 3    // px of blur where its lines fade out at the top and bottom (0 = none)
    readonly property int lyricsBarWidth: Settings.values.lyricsBarWidth ?? 240    // the bar's line, px (fixed, so the island doesn't move per line)
    readonly property int lyricsCardHeight: Settings.values.lyricsCardHeight ?? 176    // the card's lyrics, px
    readonly property real lyricsOffset: Settings.values.lyricsOffset ?? 0    // s; plus = lines come earlier
    readonly property bool lyricsBrowsers: Settings.values.lyricsBrowsers ?? false    // also what plays in a browser (its video titles go to lrclib.net too)

    // ---- Live activities ----------------------------------------------------------
    // Moments: the middle island grows for a couple of seconds to say what
    // just happened (charger, headphones, a screenshot, a copy, Wi-Fi, the
    // focus timer), then shrinks back; click does the obvious thing, hover
    // keeps it. The bubble: a small pill beside the middle island while
    // something goes on (screen recording, the focus timer, Claude Code at
    // work). services/Activities.qml; try one with
    //   qs -c mine ipc call activities preview charging
    readonly property bool activitiesEnabled: Settings.values.activitiesEnabled ?? true
    readonly property int activityDuration: Settings.values.activityDuration ?? 2500    // ms a moment stays (hover keeps it)
    readonly property int activityHeight: Settings.values.activityHeight ?? 46    // the grown island
    readonly property int activityMaxWidth: Settings.values.activityMaxWidth ?? 480
    readonly property bool activityCharging: Settings.values.activityCharging ?? true    // plugged in / unplugged
    readonly property bool activityBluetooth: Settings.values.activityBluetooth ?? true    // headphones and speakers coming and going
    readonly property bool activityScreenshot: Settings.values.activityScreenshot ?? true    // instead of the popup (the notification still goes to the list)
    readonly property bool activityClipboard: Settings.values.activityClipboard ?? true    // what you copy (never what clip-store.sh left out as a secret)
    readonly property bool activityWifi: Settings.values.activityWifi ?? true    // connected / disconnected
    readonly property bool activityFocus: Settings.values.activityFocus ?? true    // the focus timer's "Break time" / "Back to work", instead of a notification
    readonly property bool activityBubble: Settings.values.activityBubble ?? true    // in front of the clock in the middle island: recording, the focus timer, agents
    readonly property bool activityAgents: Settings.values.activityAgents ?? true    // Claude Code sessions working / waiting, in the bubble

    // ---- OSD: the volume / brightness / mic popup ---------------------------------
    // It drops in just under the middle island, in the same glass.
    readonly property int osdWidth: Settings.values.osdWidth ?? 280
    readonly property int osdHeight: Settings.values.osdHeight ?? 46
    readonly property int osdGap: Settings.values.osdGap ?? 8    // space between the islands and the OSD
    // The volume popup: a click on the bar's speaker opens it right under the
    // icon (false = the click mutes, as before).
    readonly property bool volumePopup: Settings.values.volumePopup ?? true
    readonly property int volumePopupWidth: Settings.values.volumePopupWidth ?? 290
    readonly property int volumePopupRadius: Settings.values.volumePopupRadius ?? radiusPopup
    readonly property bool volumePopupInput: Settings.values.volumePopupInput ?? true    // the mic and its devices
    readonly property int osdHideDelay: Settings.values.osdHideDelay ?? 1400    // ms it stays after the last change
    readonly property bool osdTiling: Settings.values.osdTiling ?? true    // show the tiling layout when you switch it

    // ---- Notifications -------------------------------------------------------------
    // A new notification grows out of the middle island (like a dynamic
    // island) and shrinks back into it; the bell in the right island opens
    // the list of all of them.
    readonly property int notifWidth: Settings.values.notifWidth ?? 400    // the grown island (the list cards too)
    readonly property int notifMaxHeight: Settings.values.notifMaxHeight ?? 240    // tallest the grown island gets
    readonly property int notifIslandRadius: Settings.values.notifIslandRadius ?? radiusPanel    // corners of the grown island
    readonly property real notifOpacity: Settings.values.notifOpacity ?? 0.78    // glass of the grown island (text must read well)
    readonly property int notifRadius: Settings.values.notifRadius ?? 20    // corners of the cards in the list
    readonly property int notifTimeout: Settings.values.notifTimeout ?? 5000    // ms each one stays (apps can ask for other times)
    readonly property int notifMaxPopups: Settings.values.notifMaxPopups ?? 3    // waiting in line to show; older ones go to the list
    readonly property int notifBodyLines: Settings.values.notifBodyLines ?? 2    // body lines in the island (hover shows 6)
    readonly property int notifHistoryMax: Settings.values.notifHistoryMax ?? 100    // kept in the list, also after a restart
    readonly property bool notifSound: Settings.values.notifSound ?? true    // freedesktop "message-new-instant"
    // Unread ones on the bell: "dot" (a small dot; red while an urgent one is
    // unread) or "count" (the number, 9+ past nine).
    readonly property string notifBadge: Settings.values.notifBadge ?? "dot"
    readonly property bool notifGroupByApp: Settings.values.notifGroupByApp ?? true    // the list: one card per app, click to see the rest
    readonly property bool notifReply: Settings.values.notifReply ?? true    // a Reply button when the app takes answers in place (chat apps)
    // Silent hours: Silent turns on at dndFrom and off at dndTo (24-hour
    // times; across midnight is fine). Changing it by hand sticks until then.
    readonly property bool dndSchedule: Settings.values.dndSchedule ?? false
    readonly property string dndFrom: Settings.values.dndFrom ?? "22:00"
    readonly property string dndTo: Settings.values.dndTo ?? "07:00"
    // While the focused window is fullscreen (a game, a film), new ones go
    // quietly to the list; urgent ones still show.
    readonly property bool dndFullscreen: Settings.values.dndFullscreen ?? true
    // Per app: right-click a notification (Settings → Notifications lists
    // them), e.g. { "Grab": "mute", "Telegram": "quiet" }. "mute": not shown,
    // not kept; "quiet": only in the list, no popup or sound.
    readonly property var notifRules: Settings.values.notifRules ?? ({})
    // The lock screen, under the time: each app's icon and how many it sent
    // since it locked (never what they say). Names off: icons and the total.
    readonly property bool lockNotifCounts: Settings.values.lockNotifCounts ?? true
    readonly property bool lockNotifNames: Settings.values.lockNotifNames ?? true

    // ---- Sounds (services/Sounds.qml; the files: common/sounds.js) --------------------
    // One volume for all of them (0-1, of the speaker's own volume; 0 = none).
    readonly property real soundVolume: Settings.values.soundVolume ?? 0.5
    readonly property bool soundVolumeTick: Settings.values.soundVolumeTick ?? true    // a click as the volume changes (keys, scrolling the bar)
    readonly property bool soundScreenshot: Settings.values.soundScreenshot ?? true    // a shutter when one is saved
    readonly property bool soundRecord: Settings.values.soundRecord ?? true    // recording starts / stops
    readonly property bool soundLock: Settings.values.soundLock ?? true    // locking and unlocking (lock.qml)
    readonly property bool soundPower: Settings.values.soundPower ?? true    // charger plugged in / out
    readonly property bool soundDevices: Settings.values.soundDevices ?? false    // Bluetooth devices connecting / leaving

    // ---- Launcher --------------------------------------------------------------------
    // Super (tap) or the ✿ button: the middle island stretches into a search
    // bar, results drop below it.
    readonly property int launcherWidth: Settings.values.launcherWidth ?? 600
    readonly property int launcherRows: Settings.values.launcherRows ?? 7    // results shown before it scrolls
    readonly property int launcherRowHeight: Settings.values.launcherRowHeight ?? 48
    readonly property int launcherRadius: Settings.values.launcherRadius ?? radiusPanel
    readonly property real launcherOpacity: Settings.values.launcherOpacity ?? 0.84    // glass of the open launcher
    // Shown first when you haven't typed anything (your dock apps); after
    // that, the apps you open most move up by themselves.
    readonly property var launcherFavorites: Settings.values.launcherFavorites ?? ["foot", "zen", "brave-browser-nightly", "org.gnome.Nautilus", "discord", "com.spotify.Client"]
    // What you type first picks a mode: ":" emoji (Enter copies it), "/" or
    // "~" files (fd under fileSearchRoot; Enter opens, Ctrl+Enter opens the
    // folder), "?" the web. Typing a web address offers to open it.
    readonly property bool launcherEmoji: Settings.values.launcherEmoji ?? true
    readonly property bool launcherFiles: Settings.values.launcherFiles ?? true
    readonly property bool launcherWeb: Settings.values.launcherWeb ?? true
    readonly property string webSearchUrl: Settings.values.webSearchUrl ?? "https://www.google.com/search?q=%s"    // %s = what you typed
    readonly property string fileSearchRoot: Settings.values.fileSearchRoot ?? "~"
    // Launcher: translate. "tr " and some text: one row with the translation
    // (services/Translator.qml: Google Translate, over HTTPS), asked only
    // after a pause in typing; Enter copies it. "tr ja: hello" picks the
    // language, otherwise translatePair decides the way.
    readonly property bool launcherTranslate: Settings.values.launcherTranslate ?? true
    // Launcher: app grid (▦ in the launcher, `mine launcher grid`). Every app
    // as a big tile with group chips on top (Launchpad); typing searches.
    readonly property bool launcherGridInTablet: Settings.values.launcherGridInTablet ?? true    // in tablet mode the launcher opens as the grid
    readonly property int launcherGridIconSize: Settings.values.launcherGridIconSize ?? 60    // its icons (a fifth bigger in tablet mode)

    // ---- Control center ----------------------------------------------------------------
    // ⚙ (or a click on Wi-Fi, Bluetooth, volume, battery): the right island
    // grows down into the control center.
    readonly property int ccWidth: Settings.values.ccWidth ?? 400
    readonly property int ccRadius: Settings.values.ccRadius ?? radiusPanel
    readonly property int ccPadding: Settings.values.ccPadding ?? 14    // card edge -> tiles and rows
    readonly property real ccOpacity: Settings.values.ccOpacity ?? 0.84    // glass of the open control center
    readonly property int ccTileHeight: Settings.values.ccTileHeight ?? 62
    readonly property int ccSliderHeight: Settings.values.ccSliderHeight ?? 38
    readonly property bool ccAppVolumes: Settings.values.ccAppVolumes ?? true    // a slider for each app playing sound

    // ---- Control center tiles, hotspot, song (control/ControlTiles.qml) ----------------
    // The tiles shown, in order: ids from control/ControlTiles.qml. Edit in
    // the control center (Edit under the tiles) or Settings → Control center.
    readonly property var controlTiles: Settings.values.controlTiles ?? ["wifi", "bluetooth", "silent", "awake", "nightlight", "darkmode", "screenshot", "record", "power", "rotate", "phone", "tailscale", "updates", "aiusage", "system"]
    // The hotspot's network name; "" = NetworkManager's own (Hotspot-<this computer's name>).
    // Its password is NetworkManager's (made once, kept in its profile), never here.
    readonly property string hotspotName: Settings.values.hotspotName ?? ""
    // Name that song listens to "output" (what the laptop plays: the default
    // output's monitor) or "mic"; a right click on the tile takes the other.
    readonly property string songSource: Settings.values.songSource ?? "output"
    readonly property int songListenSeconds: Settings.values.songListenSeconds ?? 12    // gives up after this (three tries)

    // ---- Phone (KDE Connect, services/Phone.qml) ---------------------------------------
    readonly property bool ccPhone: Settings.values.ccPhone ?? true    // the Phone tile in the control center (once KDE Connect is installed)
    readonly property string phoneDevice: Settings.values.phoneDevice ?? ""    // which phone: its name; "" = the first paired one
    readonly property int phoneRefresh: Settings.values.phoneRefresh ?? 30    // s between checks while the bar item or the control center shows it
    readonly property int phoneBatteryWarn: Settings.values.phoneBatteryWarn ?? 15    // % under which the bar item turns red

    // ---- Tailscale (services/Tailscale.qml) ---------------------------------------------
    readonly property bool ccTailscale: Settings.values.ccTailscale ?? true    // the Tailscale tile in the control center (once it's installed)
    readonly property int tailscalePollOpen: Settings.values.tailscalePollOpen ?? 5    // s between checks while the control center is open
    readonly property int tailscalePollBar: Settings.values.tailscalePollBar ?? 60    // s between checks while the bar item is on the bar
    readonly property int tailscaleHideAfterDays: Settings.values.tailscaleHideAfterDays ?? 30    // offline longer than this: folded under "older devices" (0 = never)
    readonly property string tailscaleCopy: Settings.values.tailscaleCopy ?? "ip"    // what a click on a device copies: "ip" | "name" (MagicDNS); right click: the other

    // ---- Dock --------------------------------------------------------------------------
    // Glass dock at the bottom middle: pinned apps, then running ones.
    readonly property int dockIconSize: Settings.values.dockIconSize ?? 40
    readonly property real dockMagnify: Settings.values.dockMagnify ?? 1.45    // how big the icon under the pointer gets (1 = off)
    readonly property real dockMagnifyRange: Settings.values.dockMagnifyRange ?? 2.6    // how far the growing reaches, in icons
    readonly property int dockSpacing: Settings.values.dockSpacing ?? 6    // between icons
    readonly property int dockPaddingMain: Settings.values.dockPaddingMain ?? 12    // dock edge -> first/last icon
    readonly property int dockPaddingCross: Settings.values.dockPaddingCross ?? 8    // above and below the icons
    readonly property int dockMarginEdge: Settings.values.dockMarginEdge ?? 6    // gap between the screen bottom and the dock
    readonly property int dockRadius: Settings.values.dockRadius ?? 20
    readonly property real dockOpacity: Settings.values.dockOpacity ?? 0.45    // glass tint
    // Near-black like the bar's middle island (Style.barIslandDark), its
    // label, previews and menu too (dark while Style.barIslandCards); by
    // default whenever the bar has that island.
    readonly property bool dockDark: Settings.values.dockDark ?? (barJoined && barCenterIsland && barIslandDark)
    readonly property bool dockReserve: Settings.values.dockReserve ?? true    // windows stay above the dock (only with "always")
    // "always": always there. "autohide": slides away; touch the bottom edge
    // under it to bring it back. "smart": there while the workspace has no
    // windows, otherwise like autohide.
    readonly property string dockBehavior: Settings.values.dockBehavior ?? "always"
    readonly property int dockHideDelay: Settings.values.dockHideDelay ?? 600    // ms after the pointer leaves before it slides away
    readonly property int dockRevealZone: Settings.values.dockRevealZone ?? 3    // px at the bottom edge that bring it back
    // Open windows: dots under a running app (one per window, up to 3; the
    // focused window's is a wide accent pill), and after resting the pointer
    // on its icon, a card with a live picture of each of its windows.
    readonly property bool dockRunningDots: Settings.values.dockRunningDots ?? true
    readonly property bool dockPreviews: Settings.values.dockPreviews ?? true
    readonly property int dockPreviewDelay: Settings.values.dockPreviewDelay ?? 400    // ms on the icon before the card shows
    readonly property int dockPreviewSize: Settings.values.dockPreviewSize ?? 140    // height of each picture
    // Pinned until you pin/unpin from the dock's right-click menu (then
    // ~/.local/state/mine-shell/dock.json wins).
    readonly property var dockPinned: Settings.values.dockPinned ?? ["foot", "zen", "brave-browser-nightly", "org.gnome.Nautilus", "discord", "com.spotify.Client"]
    // Dock badges (services/Badges.qml): a red count of the app's unread
    // messages on its icon. "both": what the app itself says (its
    // LauncherEntry D-Bus signal) or else its unread notifications; "apps"
    // or "notifications": only that one.
    readonly property bool dockBadges: Settings.values.dockBadges ?? true
    readonly property string dockBadgeSource: Settings.values.dockBadgeSource ?? "both"
    readonly property bool dockBadgeProgress: Settings.values.dockBadgeProgress ?? true    // a thin bar under the icon while the app says it's busy (a download)

    // ---- Power menu ------------------------------------------------------------------
    // ⏻ in the right island (or Super+X): five big buttons in the middle of
    // the screen. Restart, Shut down and Log out ask for a second press.
    readonly property int sessionButtonSize: Settings.values.sessionButtonSize ?? 88
    readonly property int sessionConfirmMs: Settings.values.sessionConfirmMs ?? 4000    // time to press again
    readonly property real sessionDim: Settings.values.sessionDim ?? 0.25    // darkens the screen behind (0 = off)
    // How blurred the wallpaper is behind the power menu, the cheat sheet,
    // the password dialog and the notification center (common/Backdrop.qml,
    // WallpaperFrost.qml: drawn by the shell, so it fades), like mango's blur.
    readonly property int backdropBlur: Settings.values.backdropBlur ?? 64
    readonly property int backdropDecodeWidth: 640    // the wallpaper copy they blur (px wide)
    readonly property real sessionOpacity: Settings.values.sessionOpacity ?? 0.8    // glass of the card
    // Restart to Windows (services/WindowsBoot.qml): a sixth button, only
    // when the firmware has a "Windows Boot Manager" entry; it asks for the
    // password, sets that entry for the next start only, and restarts.
    readonly property bool sessionWindows: Settings.values.sessionWindows ?? true
    // Switch to GNOME (scripts/switch-session.sh): logs out with GNOME
    // already picked on the login screen. Only while GNOME is installed.
    readonly property bool sessionGnome: Settings.values.sessionGnome ?? true

    // ---- Apps at login (services/AppRestore.qml) -------------------------------------
    // The apps open when you logged out or shut down come back at the next
    // login, each started once, its first window on the workspace it was on.
    readonly property bool restoreApps: Settings.values.restoreApps ?? true
    readonly property var restoreAppsExclude: Settings.values.restoreAppsExclude ?? []    // app ids never reopened, e.g. ["foot"]

    // ---- Password dialog (polkit) ----------------------------------------------------
    // When an app needs admin rights (pkexec, updates, Disks...).
    readonly property int polkitWidth: Settings.values.polkitWidth ?? 440
    readonly property real polkitDim: Settings.values.polkitDim ?? 0.3
    readonly property real polkitOpacity: Settings.values.polkitOpacity ?? 0.85

    // ---- Wallpaper -------------------------------------------------------------------
    // Drawn by the shell; Super+Y (or `qs -c mine ipc call wallpaper toggle`)
    // opens the picker. All colors follow the wallpaper (matugen).
    readonly property string wallpaperDir: Settings.values.wallpaperDir ?? (Quickshell.env("HOME") + "/Pictures/Wallpapers")
    readonly property int wallpaperReveal: Settings.values.wallpaperReveal ?? 1100    // ms the new one takes to spread out
    readonly property string wallpaperScheme: Settings.values.wallpaperScheme ?? "scheme-content"    // matugen -t ("m3-content" in Noctalia)
    readonly property int pickerColumns: Settings.values.pickerColumns ?? 4
    readonly property int pickerRows: Settings.values.pickerRows ?? 3    // visible before it scrolls
    readonly property int pickerThumbWidth: Settings.values.pickerThumbWidth ?? 168
    readonly property int wallpaperSlideshow: Settings.values.wallpaperSlideshow ?? 0    // minutes between new wallpapers, 0 = off
    readonly property string wallpaperSlideshowOrder: Settings.values.wallpaperSlideshowOrder ?? "random"    // "random" | "next" (folder order)
    readonly property string wallpaperDaily: Settings.values.wallpaperDaily ?? "off"    // "off" | "bing" (Bing's picture of the day, set once a day)
    // While music plays: the album cover's colors (services/ArtColors.qml).
    readonly property bool artColors: Settings.values.artColors ?? true
    readonly property string artColorsStrength: Settings.values.artColorsStrength ?? "accent"    // "accent" (the accent colors) | "full" (the glass too)
    readonly property int artColorsHold: Settings.values.artColorsHold ?? 8    // s after the music stops or pauses, then the wallpaper's again

    // ---- Light / dark ------------------------------------------------------------------
    // The shell's colors, and apps that follow the system preference
    // (services/Theme.qml). GTK apps also take the wallpaper's colors in the
    // mango session (not in GNOME or Hyprland, which keep their own).
    readonly property string themeMode: Settings.values.themeMode ?? "dark"    // "dark" | "light" | "auto" (light from sunrise to sunset)
    readonly property bool themeApps: Settings.values.themeApps ?? true    // GTK apps (Files, Settings...) take the wallpaper's colors

    // ---- Desktop -------------------------------------------------------------------
    // The time, the date and the weather drawn on the wallpaper (under the
    // windows, clicks go through).
    readonly property bool desktopClock: Settings.values.desktopClock ?? true
    readonly property string desktopClockPosition: Settings.values.desktopClockPosition ?? "center"    // center | top-left | top-right | bottom-left | bottom-right
    readonly property real desktopClockScale: Settings.values.desktopClockScale ?? 1    // 1 = 96 px digits
    readonly property bool desktopClockShowWeather: Settings.values.desktopClockShowWeather ?? true
    // Cards on the desktop next to the clock, in this order: "music" (only
    // while something plays), "system" (CPU, RAM, temperature, network),
    // "calendar" (this month, today's events).
    readonly property var desktopWidgets: Settings.values.desktopWidgets ?? ["music"]
    readonly property string desktopWidgetsSide: Settings.values.desktopWidgetsSide ?? "auto"    // auto | beside | stacked (above the clock at the bottom, under it elsewhere)
    readonly property real desktopWidgetOpacity: Settings.values.desktopWidgetOpacity ?? 0.8    // their glass (mango doesn't blur behind the desktop)
    readonly property real desktopMusicTint: Settings.values.desktopMusicTint ?? 0.55    // the cover's colors in the music card's glass (0 = plain glass)

    // ---- Night light -----------------------------------------------------------------
    // Warmer colors, by wlsunset (sudo pacman -S wlsunset). "off", "on" (all
    // the time) or "schedule": sunset to sunrise at the weather place, or
    // nightLightFrom to nightLightTo when nightLightUseLocation is false.
    readonly property string nightLightMode: Settings.values.nightLightMode ?? "off"
    readonly property int nightLightTemp: Settings.values.nightLightTemp ?? 4000    // Kelvin; lower = warmer (6500 = normal)
    readonly property bool nightLightUseLocation: Settings.values.nightLightUseLocation ?? true
    readonly property string nightLightFrom: Settings.values.nightLightFrom ?? "20:00"
    readonly property string nightLightTo: Settings.values.nightLightTo ?? "07:00"

    // ---- Clipboard -----------------------------------------------------------------------
    // Super+V: the middle island grows into your clipboard history.
    readonly property int clipWidth: Settings.values.clipWidth ?? 560
    readonly property int clipRows: Settings.values.clipRows ?? 7    // entries shown before it scrolls
    readonly property int clipRowHeight: Settings.values.clipRowHeight ?? 52
    readonly property bool clipAutoPaste: Settings.values.clipAutoPaste ?? true    // paste right away into the app you were in
    // API keys, tokens, private keys and the codes your phone's notifications
    // just showed aren't kept in the history (scripts/clip-store.sh).
    readonly property bool clipSkipSecrets: Settings.values.clipSkipSecrets ?? true

    // ---- Screenshots -----------------------------------------------------------------
    // Print / Super+Shift+S: the screen freezes, drag a region or click a
    // window. Ctrl+Print: the whole screen at once. Saved, copied, and a
    // notification with the picture (click: open; Edit; Delete).
    readonly property string screenshotDir: Settings.values.screenshotDir ?? (Quickshell.env("HOME") + "/Pictures/Screenshots")
    readonly property real screenshotDim: Settings.values.screenshotDim ?? 0.45    // darkness outside the selection
    readonly property bool screenshotConfirm: Settings.values.screenshotConfirm ?? false    // true: adjust the region, then Enter
    readonly property bool screenshotNotify: Settings.values.screenshotNotify ?? true
    // Edit (E in the overlay, and the notification's Edit): "markup" draws on
    // it right in the overlay (pen, arrow, box, text, blur); "swappy" opens
    // swappy after saving instead.
    readonly property string screenshotEditor: Settings.values.screenshotEditor ?? "markup"
    readonly property int screenshotPixelSize: Settings.values.screenshotPixelSize ?? 16    // the blur's blocks, in real pixels
    // Super+Shift+T: copy the text in a region (tesseract). "auto" = English,
    // plus Vietnamese once tesseract-data-vie is installed; or e.g. "eng+vie".
    readonly property string ocrLanguages: Settings.values.ocrLanguages ?? "auto"
    // Scan a QR code (Q), Google Lens (L) and Translate (D) in the
    // screenshot overlay (services/Screenshot.qml, services/Translator.qml).
    // translatePair "vi:en": your language, then the other one; text that
    // looks like yours is translated to the other, anything else to yours.
    // The text read off the screen goes to Google Translate, over HTTPS.
    readonly property string translatePair: Settings.values.translatePair ?? "vi:en"

    // ---- Screen recording --------------------------------------------------------------
    // The Record tile, Super+Shift+R (screen) / Super+Alt+R (region): the
    // bar shows a red dot with the time; click it (or the key again) to stop.
    readonly property string recordDir: Settings.values.recordDir ?? (Quickshell.env("HOME") + "/Videos/Recordings")
    readonly property bool recordAudio: Settings.values.recordAudio ?? false    // also what you hear (not the mic)
    readonly property bool recordHardware: Settings.values.recordHardware ?? false    // encode on the GPU (VA-API): lighter, bigger files

    // ---- Privacy dots and typing language ------------------------------------------------
    // "Privacy dots" in Bar items (bar/PrivacyItem.qml, services/Privacy.qml):
    // orange while an app records the microphone (click: mute it), green
    // while the camera is on, purple while the screen is shared.
    readonly property color privacyMicColor: Settings.values.privacyMicColor ?? "#ff9f0a"
    readonly property color privacyCameraColor: Settings.values.privacyCameraColor ?? "#30d158"
    readonly property color privacyShareColor: Settings.values.privacyShareColor ?? "#bf5af2"
    readonly property int privacyNamesWidth: Settings.values.privacyNamesWidth ?? 180    // the apps' names on hover, at most
    readonly property bool privacyCamera: Settings.values.privacyCamera ?? true    // false: no camera dot (nothing is read for it)
    readonly property int privacyCameraPoll: Settings.values.privacyCameraPoll ?? 2000    // ms between looks at the camera's power state
    // While the screen is shared (or you record it), new notifications go
    // quietly to the list; urgent ones still show.
    readonly property bool privacyQuietSharing: Settings.values.privacyQuietSharing ?? true
    // fcitx5's tray icon is drawn as EN / VI; switching (Super+Space) shows
    // the OSD "English" / "Tiếng Việt".
    readonly property bool osdIme: Settings.values.osdIme ?? true

    // ---- Keys and locking ----------------------------------------------------------------
    readonly property real keyVolumeStep: Settings.values.keyVolumeStep ?? 0.03    // volume keys (3%)
    readonly property real keyBrightnessStep: Settings.values.keyBrightnessStep ?? 0.05    // brightness keys (5%)
    readonly property bool lockBeforeSleep: Settings.values.lockBeforeSleep ?? true    // lock when the lid closes / before suspend

    // ---- Screen corners -------------------------------------------------------------------
    // Rounded corners on the screen, like a Mac display (above everything,
    // never in the way of a click).
    readonly property bool cornersEnabled: Settings.values.cornersEnabled ?? true
    readonly property int cornerRadius: Settings.values.cornerRadius ?? 14
    readonly property color cornerColor: Settings.values.cornerColor ?? "black"

    // ---- Idle ------------------------------------------------------------------------------
    // When you leave the laptop alone (seconds, 0 = never). Videos and calls
    // that ask to stay awake, and "Keep awake" in the control center, hold
    // these off. Any input brings everything back.
    readonly property int dimAfter: Settings.values.dimAfter ?? 180    // the screen dims
    readonly property int screenOffAfter: Settings.values.screenOffAfter ?? 0    // the screen goes off (0 until tried, then 300: see services/Idle.qml)
    readonly property int lockAfter: Settings.values.lockAfter ?? 600    // the lock screen comes up
    readonly property real idleDimLevel: Settings.values.idleDimLevel ?? 0.1    // brightness while dimmed (0-1)
    readonly property int lockedScreenOffAfter: Settings.values.lockedScreenOffAfter ?? 0    // the screen goes off this long after the lock screen is up, OLED burn-in (0 until tried, then 30)
    readonly property int suspendOnBatteryAfter: Settings.values.suspendOnBatteryAfter ?? 0    // on battery: the laptop sleeps, not while something plays (e.g. 1800)
    // Presence sensor in the camera (services/Presence.qml): lock as soon as
    // nobody is in front of the screen, and no dimming while someone looks.
    // Read only while idle; each read wakes the camera ~2 s.
    readonly property bool presenceLock: Settings.values.presenceLock ?? false
    readonly property int presenceIdle: Settings.values.presenceIdle ?? 30    // s without input before the first read
    readonly property int presenceEvery: Settings.values.presenceEvery ?? 4    // s between reads
    readonly property int presenceAwayFor: Settings.values.presenceAwayFor ?? 10    // s with nobody there: lock
    readonly property int presenceDimHold: Settings.values.presenceDimHold ?? 600    // the dim waits at most this long for someone looking

    // ---- Auto brightness (services/AutoBrightness.qml) -------------------------------------
    // The screen follows the light sensor, and learns from the changes you
    // make yourself (kept in ~/.local/state/mine-shell/autobright.json).
    readonly property bool autoBrightness: Settings.values.autoBrightness ?? false
    readonly property real autoBrightnessMin: Settings.values.autoBrightnessMin ?? 0.1    // never darker than this unless you make it darker yourself (never under 5%)
    readonly property real autoBrightnessMax: Settings.values.autoBrightnessMax ?? 1    // never brighter than this unless you make it brighter yourself
    readonly property real autoBrightnessGlide: Settings.values.autoBrightnessGlide ?? 4    // s a change takes (a glide in 1% steps)
    readonly property real autoBrightnessHold: Settings.values.autoBrightnessHold ?? 10    // min it leaves your own change alone (or until the light halves or doubles)

    // ---- Battery care (services/BatteryCare.qml) -----------------------------------------
    readonly property bool batterySaverOnBattery: Settings.values.batterySaverOnBattery ?? true    // unplugged: Power saver; plugged in: back to before
    readonly property int batteryWarnLow: Settings.values.batteryWarnLow ?? 15    // % for the "Battery low" notification (0 = off)
    readonly property int batteryWarnCritical: Settings.values.batteryWarnCritical ?? 5    // % for the urgent one, with sound even when Silent (0 = off)
    readonly property int batteryFullNotice: Settings.values.batteryFullNotice ?? 0    // % for "Battery charged" while plugged in (0 = off)
    // Headphones, mouse, game pad… (services/Peripherals.qml): under this %
    // a notification says so, once; the bar item turns red (0 = off).
    readonly property int deviceBatteryWarn: Settings.values.deviceBatteryWarn ?? 15

    // ---- Battery popup (services/BatteryHealth.qml, control/BatteryPopup.qml) ---------------
    // A click on the bar's battery: the charge over the last hours (UPower's
    // history) and the battery's health (wear, cycles, capacity now / new).
    readonly property bool batteryPopup: Settings.values.batteryPopup ?? true    // false: the click opens the control center, as before
    readonly property int batteryPopupWidth: Settings.values.batteryPopupWidth ?? 330
    readonly property int batteryGraphHours: Settings.values.batteryGraphHours ?? 24    // how far back the graph goes

    // ---- Focus timer (services/FocusTimer.qml, "Focus timer" in Bar items) ------------------
    readonly property int focusMinutes: Settings.values.focusMinutes ?? 25    // work
    readonly property int focusBreak: Settings.values.focusBreak ?? 5    // short break
    readonly property int focusLongBreak: Settings.values.focusLongBreak ?? 15    // long break
    readonly property int focusRounds: Settings.values.focusRounds ?? 4    // a long break after this many rounds of work
    readonly property bool focusSilent: Settings.values.focusSilent ?? false    // Silent while working

    // ---- Claude Code sessions (services/Agents.qml, "Claude Code" in Bar items) -------------
    // A terminal running Claude Code whose ◐ turned ✳: done, or waiting for
    // you (a permission prompt looks the same), while you're in another window.
    readonly property bool agentsNotify: Settings.values.agentsNotify ?? true    // a notification; Show goes to its window
    readonly property int agentsHold: Settings.values.agentsHold ?? 3    // s the ✳ must stay (shorter stops between steps don't count)
    readonly property bool agentsSound: Settings.values.agentsSound ?? true    // a chime with it (not while Silent)

    // ---- Lock screen ---------------------------------------------------------------------
    // lock.qml (~/.local/bin/qs-lock starts it), in one of two styles:
    // "mac" (the time big at the top, you and the password at the bottom)
    // or "panel" (the bar's glass around a panel with cards).
    readonly property string lockStyle: Settings.values.lockStyle ?? "mac"    // "mac" | "panel"
    readonly property int lockHideAfter: Settings.values.lockHideAfter ?? 10    // mac: s without input until only the time shows (0 = never)
    readonly property string lockClockFont: Settings.values.lockClockFont ?? ""    // mac: the time's font; "" = SF Pro Rounded if installed, else the bar's font
    // Simple style (and the login screen) on a bright wallpaper: the field
    // and the pills get a darker tint, the words a stronger shadow and the
    // top and bottom a little more shade, as much as the picture behind each
    // needs (lock/WallpaperLight.qml measures it). "auto": only where it's
    // bright (a dark wallpaper looks exactly as before), "light": never (the
    // see-through look everywhere), "dark": always the darker look.
    readonly property string lockFieldContrast: Settings.values.lockFieldContrast ?? "auto"
    readonly property real lockContrastFrom: Settings.values.lockContrastFrom ?? 0.45    // brightness (0-1) where the help starts
    readonly property real lockContrastTo: Settings.values.lockContrastTo ?? 0.65    // and where it's at its strongest
    readonly property bool lockFace: Settings.values.lockFace ?? true    // unlock by looking at the IR camera (Howdy; set up by setup/face-setup.sh), beside the password
    readonly property real lockWallpaperBlur: Settings.values.lockWallpaperBlur ?? 0.9    // 0-1, the wallpaper behind (panel style)
    readonly property real lockOpacity: Settings.values.lockOpacity ?? 0.6    // glass of the panel and the islands (over the lock's own blur)
    readonly property int lockRadius: Settings.values.lockRadius ?? 36    // corners of the panel
    readonly property int lockWeatherTempSize: Settings.values.lockWeatherTempSize ?? 30    // the temperature on the weather card
    readonly property bool lockShowWeather: Settings.values.lockShowWeather ?? true
    readonly property bool lockShowFetch: Settings.values.lockShowFetch ?? true    // user@host, kernel, uptime...
    readonly property bool lockShowMedia: Settings.values.lockShowMedia ?? true
    readonly property bool lockShowResources: Settings.values.lockShowResources ?? true    // CPU, memory, temperature, battery
    readonly property bool lockShowCalendar: Settings.values.lockShowCalendar ?? true

    // ---- Calendar & weather ---------------------------------------------------------------
    // Click the clock: the middle island grows into a month calendar with the
    // weather (Open-Meteo, no account needed).
    readonly property int calendarWidth: Settings.values.calendarWidth ?? 380
    readonly property int calendarRadius: Settings.values.calendarRadius ?? radiusPanel
    readonly property int calendarDaySize: Settings.values.calendarDaySize ?? 40    // today's big day number
    readonly property real calendarOpacity: Settings.values.calendarOpacity ?? 0.84    // glass of the open calendar
    readonly property bool weatherEnabled: Settings.values.weatherEnabled ?? true
    readonly property string weatherCity: Settings.values.weatherCity ?? "Ho Chi Minh City"
    readonly property real weatherLatitude: Settings.values.weatherLatitude ?? 10.82
    readonly property real weatherLongitude: Settings.values.weatherLongitude ?? 106.63
    readonly property int weatherRefreshMinutes: Settings.values.weatherRefreshMinutes ?? 30
    readonly property int weatherHours: Settings.values.weatherHours ?? 5    // hours shown ahead
    // Your events in the calendar (and the next one next to the clock): the
    // addresses of calendar files (.ics), spaces between. Google Calendar:
    // Settings → your calendar → "Secret address in iCal format". Secret!
    readonly property string calendarIcsUrls: Settings.values.calendarIcsUrls ?? ""
    readonly property int calendarRefreshMinutes: Settings.values.calendarRefreshMinutes ?? 15
    readonly property bool clockNextEvent: Settings.values.clockNextEvent ?? true    // the next event next to the clock, within the hour

    // ---- Window switcher -------------------------------------------------------------
    // Alt+Tab: your windows, most recent first; let go of Alt to switch.
    readonly property int switcherIconSize: Settings.values.switcherIconSize ?? 52
    readonly property int switcherCell: Settings.values.switcherCell ?? 84    // one window's square
    readonly property int switcherRadius: Settings.values.switcherRadius ?? radiusPanel
    readonly property real switcherOpacity: Settings.values.switcherOpacity ?? 0.86    // glass of the strip
    readonly property int switcherIdleCommit: Settings.values.switcherIdleCommit ?? 700    // ms with nothing pressed: switch anyway (quick taps)

    // ---- Overview ----------------------------------------------------------------------
    // Super+O / the hot corner: every workspace as a small copy of the screen
    // in a grid, its windows where they really are, as pictures.
    readonly property string overviewHotCorner: Settings.values.overviewHotCorner ?? "bottom-left"    // "off" | "top-left" | "top-right" | "bottom-left" | "bottom-right"
    readonly property int overviewHotCornerDelay: Settings.values.overviewHotCornerDelay ?? 150    // ms the pointer rests in the corner first
    readonly property bool overviewShowAll: Settings.values.overviewShowAll ?? false    // all 9 workspaces (else: the ones with windows, yours and a "+")
    readonly property int overviewColumns: Settings.values.overviewColumns ?? 3    // workspaces per row, at most
    readonly property int overviewGap: Settings.values.overviewGap ?? 24    // between the workspaces
    readonly property int overviewCardRadius: Settings.values.overviewCardRadius ?? 18    // corners of a workspace
    readonly property bool overviewLive: Settings.values.overviewLive ?? true    // pictures of the windows (off: their icons)
    readonly property int overviewRefresh: Settings.values.overviewRefresh ?? 700    // ms: your workspace's pictures again (the others ~4x slower; 0 = only when it opens)
    readonly property real overviewDim: Settings.values.overviewDim ?? 0.35    // darkens the screen behind (mango blurs it)
    readonly property int overviewOpenMs: Settings.values.overviewOpenMs ?? 500    // the zoom out of your workspace
    readonly property int overviewCloseMs: Settings.values.overviewCloseMs ?? 440    // the zoom into the one you picked
    // The zoom's curve (cubic bezier x1, y1, x2, y2). Keep the start gentle:
    // a steep one moves a big part of the way in one frame (looks like a jump).
    readonly property var overviewCurve: {
        const c = Settings.values.overviewCurve;
        return (Array.isArray(c) && c.length === 4 ? c : [0.25, 0.6, 0.1, 1]).concat([1, 1]);
    }

    // ---- Settings window (Super+, / ⚙) ----------------------------------------------
    // A see-through window over mango's blur (like the terminal's glass), a
    // glass sidebar floating inside it and glass cards for the groups.
    readonly property real settingsOpacity: Settings.values.settingsOpacity ?? 0.74    // the window's tint over the blur
    readonly property real settingsSidebarOpacity: Settings.values.settingsSidebarOpacity ?? 0.42    // the sidebar's glass, over the window's tint
    readonly property real settingsCardOpacity: Settings.values.settingsCardOpacity ?? 0.5    // the groups' glass
    readonly property int settingsSidebarWidth: Settings.values.settingsSidebarWidth ?? 236
    readonly property int settingsInset: Settings.values.settingsInset ?? 8    // window edge -> sidebar
    // mango draws the window's corners (border_radius in ~/.config/mango/
    // config.conf); the sidebar's corners follow them (Style.inner).
    readonly property int settingsWindowRadius: Settings.values.settingsWindowRadius ?? 12
    readonly property int settingsCardRadius: Settings.values.settingsCardRadius ?? 18
    readonly property bool settingsSectionColors: Settings.values.settingsSectionColors ?? true    // each section's icon on a colored square

    // ---- Shortcut cheat sheet ----------------------------------------------------------
    // Super+/: every mango shortcut, read from mango's config, in columns.
    readonly property int cheatSheetColumns: Settings.values.cheatSheetColumns ?? 0    // 0 = as many as fit (up to 4)
    readonly property int cheatSheetColumnWidth: Settings.values.cheatSheetColumnWidth ?? 400
    readonly property int cheatSheetRowHeight: Settings.values.cheatSheetRowHeight ?? 28
    readonly property int cheatSheetChipHeight: Settings.values.cheatSheetChipHeight ?? 22    // one key
    readonly property int cheatSheetRadius: Settings.values.cheatSheetRadius ?? radiusDialog
    readonly property real cheatSheetOpacity: Settings.values.cheatSheetOpacity ?? 0.86    // glass of the card
    readonly property real cheatSheetDim: Settings.values.cheatSheetDim ?? 0.25    // darkens the screen behind (0 = off)

    // ---- On-screen keyboard (osk/, services/OskState.qml) ------------------------------
    // Slides up along the bottom of the built-in screen when it folds back into
    // a tablet (mango runs `mine osk fold`), or from the bar's keyboard item.
    // Windows shrink above it; it types into the window you're in (wtype) and
    // never takes the keyboard focus itself.
    readonly property bool oskAutoTablet: Settings.values.oskAutoTablet ?? true    // up in tablet mode, away when folded back
    readonly property int oskHeight: Settings.values.oskHeight ?? 300    // four rows of keys and the glass around them
    readonly property int oskMaxWidth: Settings.values.oskMaxWidth ?? 1100    // wider screens: centered at this width
    readonly property int oskKeyRadius: Settings.values.oskKeyRadius ?? 10
    readonly property real oskOpacity: Settings.values.oskOpacity ?? 0.55    // glass tint; mango blurs what's behind it
    readonly property int oskRepeatDelay: Settings.values.oskRepeatDelay ?? 450    // ms holding ⌫ or an arrow before it repeats
    readonly property int oskRepeatInterval: Settings.values.oskRepeatInterval ?? 70    // ms between repeats

    // ---- Tablet (services/TabletMode.qml, services/AutoRotate.qml) ---------------------
    // Turn the built-in screen with the tablet: "off", "tablet" (only while
    // folded back) or "always". The accelerometer is only read while it's on.
    readonly property string rotateScreen: Settings.values.rotateScreen ?? "off"
    // The laptop's own keyboard and touchpad when folded back (laid flat):
    // libinput turns them off in tablet mode; true keeps them on. Takes
    // scripts/tablet-keyboard.sh run with sudo (Settings copies the command)
    // and a new login; the hardware itself may still cut them past ~180°.
    readonly property bool tabletKeepKeyboard: Settings.values.tabletKeepKeyboard ?? false

    // ---- USB drives (services/Drives.qml, "USB drives" in Bar items) -------------------------
    // A notification when one is plugged in (Open / Eject), and the bar item
    // with its popup while one is there.
    readonly property bool drivesWatch: Settings.values.drivesWatch ?? true    // watch for them at all (udisksctl monitor)
    readonly property bool drivesNotify: Settings.values.drivesNotify ?? true    // "USB drive plugged in"
    readonly property int drivesPopupWidth: Settings.values.drivesPopupWidth ?? 330

    // ---- Screen time, breaks, AI usage (services/ScreenTime.qml, Breaks.qml, AiUsage.qml) -----
    // Screen time: the focused app's time while you're really there (screen
    // on, not locked or asleep, some input in the last screenTimeIdle s; a
    // fullscreen window or a playing video goes on counting). "Screen time"
    // in Bar items and in the control center's tiles; kept 30 days.
    readonly property bool screenTime: Settings.values.screenTime ?? true
    readonly property int screenTimeIdle: Settings.values.screenTimeIdle ?? 300    // s without input until it stops counting
    readonly property int screenTimeDays: Settings.values.screenTimeDays ?? 30    // days kept
    readonly property int screenTimePopupWidth: Settings.values.screenTimePopupWidth ?? 340
    // Break reminders: a notification after breakAfter min on the screen
    // without a real break (away breakResetAfter min or more): Snooze, or
    // Take a break (a breakLength min countdown on the screen). Quiet while
    // fullscreen, sharing or recording the screen, or Silent.
    readonly property bool breakReminders: Settings.values.breakReminders ?? true
    readonly property int breakAfter: Settings.values.breakAfter ?? 50    // min
    readonly property int breakResetAfter: Settings.values.breakResetAfter ?? 5    // min away that count as a break
    readonly property int breakSnooze: Settings.values.breakSnooze ?? 10    // min
    readonly property int breakLength: Settings.values.breakLength ?? 5    // min, the countdown
    readonly property real breakDim: Settings.values.breakDim ?? 0.55    // darkens the screen behind the countdown
    readonly property bool breakEyes: Settings.values.breakEyes ?? false    // 20-20-20: look away now and then
    readonly property int breakEyesEvery: Settings.values.breakEyesEvery ?? 20    // min
    // AI usage ("AI usage" in Bar items): Claude's and Codex's limits, read
    // with their apps' own sign-in (never refreshed or written).
    readonly property int aiUsagePoll: Settings.values.aiUsagePoll ?? 5    // min between checks while shown
    readonly property bool aiUsageNotify: Settings.values.aiUsageNotify ?? true    // once per window at each threshold
    readonly property int aiUsageWarnAt: Settings.values.aiUsageWarnAt ?? 80    // % (when the answer doesn't say)
    readonly property int aiUsageCriticalAt: Settings.values.aiUsageCriticalAt ?? 95    // %
    readonly property color aiUsageWarnColor: Settings.values.aiUsageWarnColor ?? "#ff9f0a"    // the rings past warnAt (critical: the error color)
    readonly property int aiUsagePopupWidth: Settings.values.aiUsagePopupWidth ?? 340

    // ---- Timer, stopwatch, alarms (services/Timers.qml) --------------------------------
    // The control center's Timer, Stopwatch and Alarm tiles (and their page).
    // A timer that ends or an alarm rings until Stop, then stops by itself.
    readonly property int timersSnoozeMinutes: Settings.values.timersSnoozeMinutes ?? 9
    readonly property int timersRingSeconds: Settings.values.timersRingSeconds ?? 60    // the sound stops by itself after this (the notification stays)
    readonly property bool timersRingInSilent: Settings.values.timersRingInSilent ?? true    // rings (and pops up) in Silent too
    readonly property real timersVolume: Settings.values.timersVolume ?? 0.8    // the alarm sound (0-1), of the system volume

    // ---- Drawing on the screen (services/Ink.qml, ink/) ---------------------------------
    // The pen, the mouse and (inkTouch) a finger draw over everything; a small
    // toolbar to drag around. mango doesn't blur behind it, so its glass is
    // thicker (inkToolbarOpacity).
    readonly property bool inkTouch: Settings.values.inkTouch ?? false    // a finger draws too (a palm resting on the screen would as well)
    readonly property real inkFadeSeconds: Settings.values.inkFadeSeconds ?? 0    // strokes fade away after this long (0 = they stay)
    readonly property real inkToolbarOpacity: Settings.values.inkToolbarOpacity ?? 0.9

    // ---- Notes and to-dos (services/Notes.qml, notes/) ---------------------------------
    // The notes panel (the Notes tile, a click on the desktop's notes card)
    // sits at the right, under the bar; the card goes on the desktop with
    // "notes" in desktopWidgets.
    readonly property int notesWidth: Settings.values.notesWidth ?? 420
    readonly property int notesHeight: Settings.values.notesHeight ?? 600    // at most (less above the on-screen keyboard)
    readonly property real notesOpacity: Settings.values.notesOpacity ?? 0.86    // the panel's glass
    readonly property bool notesCollapseDone: Settings.values.notesCollapseDone ?? true    // a checklist's ticked items folded under "N done"

    // A color with a new alpha (0-1).
    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }
}
