//@ pragma Env QT_QPA_PLATFORMTHEME=none
//@ pragma Env QT_QPA_PLATFORMTHEME_QT6=none
//@ pragma IconTheme ZorinGrey-Dark
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.bar
import qs.osd
import qs.dock
import qs.notifications
import qs.launcher
import qs.clipboard
import qs.control
import qs.session
import qs.polkit
import qs.services
import qs.wallpaper
import qs.screenshot
import qs.calendar
import qs.nowplaying
import qs.switcher
import qs.settings
import qs.desktop
import qs.cheatsheet
import qs.sysmon
import qs.overview
import qs.osk
import qs.activity
import qs.updates
import qs.ink
import qs.notes

// My own shell for mango. Run: qs -c mine   (or: mine on, see ~/.local/bin/mine)
// The bar (three glass islands), the OSD (volume / brightness / mic),
// notifications (they grow out of the middle island; the list is behind the
// bell), the launcher (Super), the clipboard history (Super+V), the control
// center (⚙ / Super+N, out of the right island), the dock, the power menu
// (⏻ / Super+X), the password dialog for admin rights (polkit), the
// wallpaper with colors made from it (Super+Y), screenshots (Print,
// Super+Shift+S, Ctrl+Print), screen recording (Super+Shift+R, Super+Alt+R)
// and the color picker (Super+Shift+C), the media keys, locking before sleep,
// dimming / screen off / lock when idle, the calendar with the weather
// (click the clock), the Alt+Tab window switcher, the Settings window
// (Super+, / ⚙) and the shortcut cheat sheet (Super+/).
// Also the clock on the desktop, night light, reopening your apps at login,
// and the lock screen (lock.qml, a second entry point started by
// ~/.local/bin/qs-lock). Nothing of Noctalia's runs any more.
//
//   common/Style.qml   every size, opacity and font, with its default value
//   common/Motion.qml  animation curves and timings
//   common/Colors.qml  reads the wallpaper colors (services/Wallpaper.qml makes them)
//   bar/               the islands, one file per widget (which ones, in what
//                      order: Settings → Bar items, or Style.barLeft/…)
//   osd/               the volume / brightness / mic popup
//   notifications/     the notification island and the list
//   launcher/          the app launcher
//   calendar/          the calendar and weather (click the clock)
//   switcher/          the Alt+Tab window switcher
//   settings/          the Settings window (what you change there is kept in
//                      ~/.local/state/mine-shell/settings.json)
//   clipboard/         the clipboard history
//   control/           the control center
//   dock/              the dock
//   session/           the power menu
//   polkit/            the password dialog for admin rights
//   wallpaper/         the wallpaper and its picker
//   desktop/           the clock and weather on the wallpaper
//   screenshot/        the screenshot overlay (freeze, pick, cut)
//   lock/              the lock screen's parts (lock.qml starts it)
//   cheatsheet/        the keyboard shortcut cheat sheet (Super+/)
//   sysmon/            the System popup (click a CPU / memory / … item on the bar)
//   overview/          the overview (Super+O, the hot corner): workspaces and live windows
//   osk/               the on-screen keyboard (tablet mode, or the bar's keyboard item)
//   activity/          live activities: moments out of the middle island
//   services/          data and state (mango, sound, backlight, notifications…)
//
// The pragmas above keep it lean: no GTK theme plugin is loaded (the
// session asks for gtk3; icons come straight from ZorinGrey-Dark instead),
// and there's no UseQApplication, so no Qt Widgets (tray menus are drawn by
// the shell, bar/TrayMenu.qml).
ShellRoot {
    id: shell

    Variants {
        model: Quickshell.screens

        Bar {}
    }

    // The dock at the bottom.
    Variants {
        model: Quickshell.screens

        Dock {}
    }

    // The OSD window is only created while it shows.
    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property ShellScreen modelData

            LazyLoader {
                active: OsdState.mapped

                OsdWindow {
                    modelData: screenScope.modelData
                }
            }
        }
    }

    // Live activities: a moment grows out of the middle island (charger,
    // headphones, a screenshot, a copy, Wi-Fi, the focus timer). The window
    // exists only while one shows. The ongoing ones (recording, the focus
    // timer, agents) are a segment of the bar's middle island.
    Variants {
        model: Quickshell.screens

        Scope {
            id: momentScope
            required property ShellScreen modelData

            LazyLoader {
                active: Activities.mapped

                MomentWindow {
                    modelData: momentScope.modelData
                }
            }
        }
    }

    // From a terminal: qs -c mine ipc call activities preview charging
    // (unplugged bluetooth screenshot copy picture color ocr wifi wifioff
    // focus, or the bubble's recording timer agents for 8 s).
    IpcHandler {
        target: "activities"

        function preview(kind: string): string {
            return Activities.preview(kind) ? "ok" : "can't now (off, or a panel is open)";
        }
    }

    // Notifications. Notifs.popupsMapped also starts the notification
    // daemon right at startup (it lives in the Notifs singleton).
    Variants {
        model: Quickshell.screens

        Scope {
            id: popupScope
            required property ShellScreen modelData

            LazyLoader {
                active: Notifs.popupsMapped

                IslandNotif {
                    modelData: popupScope.modelData
                }
            }

            LazyLoader {
                active: Notifs.centerMapped

                NotifCenter {
                    modelData: popupScope.modelData
                }
            }
        }
    }

    // The launcher: only exists while open.
    Variants {
        model: Quickshell.screens

        Scope {
            id: launcherScope
            required property ShellScreen modelData

            LazyLoader {
                active: LauncherState.mapped

                LauncherWindow {
                    modelData: launcherScope.modelData
                }
            }
        }
    }

    // The control center: only exists while open.
    Variants {
        model: Quickshell.screens

        Scope {
            id: controlScope
            required property ShellScreen modelData

            LazyLoader {
                active: ControlState.mapped

                ControlWindow {
                    modelData: controlScope.modelData
                }
            }
        }
    }

    // The volume popup (click the bar's speaker), only on the screen it was
    // opened on and only while needed.
    Variants {
        model: Quickshell.screens

        Scope {
            id: volumeScope
            required property ShellScreen modelData

            LazyLoader {
                active: VolumeState.mapped && VolumeState.screen === volumeScope.modelData.name

                VolumeWindow {
                    modelData: volumeScope.modelData
                }
            }
        }
    }

    // The updates panel (click the bar's updates item), only on the screen
    // it was opened on and only while needed.
    Variants {
        model: Quickshell.screens

        Scope {
            id: updatesScope
            required property ShellScreen modelData

            LazyLoader {
                active: UpdatesState.mapped && UpdatesState.screen === updatesScope.modelData.name

                UpdatesWindow {
                    modelData: updatesScope.modelData
                }
            }
        }
    }

    // Super+N runs `mine control-center`, which calls this.
    // Pages: main, wifi, bluetooth, audio, phone, tailscale.
    IpcHandler {
        id: controlIpc
        target: "control"

        function toggle(page: string): void {
            ControlState.toggle(page);
        }
        function close(): void {
            ControlState.close();
        }
        // Super+, : the Settings window.
        function settings(): void {
            Panels.settings();
        }
    }

    // Tailscale (services/Tailscale.qml; on and off need you as its
    // operator: sudo tailscale set --operator=$USER, once).
    // qs -c mine ipc call tailscale status | up | down | page
    IpcHandler {
        target: "tailscale"

        function status(): string {
            return Tailscale.summary;
        }
        function up(): void {
            Tailscale.setRunning(true);
        }
        function down(): void {
            Tailscale.setRunning(false);
        }
        function page(): void {
            ControlState.toggle("tailscale");
        }
    }

    // The battery and USB drive popups (a click on the bar's battery or USB
    // item: control/BarPopupWindow.qml), only on the screen they were opened
    // on and only while needed; tidied up after like the others below.
    Variants {
        model: Quickshell.screens

        Scope {
            id: barPopupScope
            required property ShellScreen modelData

            LazyLoader {
                active: BarPopupState.mapped && BarPopupState.screen === barPopupScope.modelData.name

                BarPopupWindow {
                    modelData: barPopupScope.modelData
                }
            }
        }
    }
    Connections {
        target: BarPopupState
        function onMappedChanged() {
            if (!BarPopupState.mapped)
                tidy.restart();
        }
    }
    // USB drives (services/Drives.qml): reading this starts watching for
    // them with the shell (the notification needs no bar item).
    readonly property bool drivesWatching: Drives.enabled

    // qs -c mine ipc call battery popup | status
    // (status: JSON with the charge, health, wear, cycles and history points.)
    IpcHandler {
        target: "battery"

        function popup(): void {
            BarPopupState.toggle("battery", "", Qt.rect(0, 0, 0, 0));
        }
        function status(): string {
            BatteryHealth.refresh();
            return BatteryHealth.status();
        }
    }

    // qs -c mine ipc call drives popup | status | open <key> | eject <key>
    // (status: JSON list; a key is the drive's name, e.g. sdb, or its key.)
    IpcHandler {
        target: "drives"

        function popup(): void {
            BarPopupState.toggle("drives", "", Qt.rect(0, 0, 0, 0));
        }
        function status(): string {
            return Drives.status();
        }
        function open(key: string): void {
            Drives.open(key);
        }
        function eject(key: string): void {
            Drives.eject(key);
        }
    }

    // Control center extras (ctl): name that song, airplane mode, hotspot.
    // qs -c mine ipc call song listen | stop | status
    // qs -c mine ipc call airplane toggle | on | off | status
    // qs -c mine ipc call hotspot status | off | page
    IpcHandler {
        target: "song"

        function listen(): void {
            SongRec.toggle("");
        }
        function stop(): void {
            SongRec.stop();
        }
        function status(): string {
            return SongRec.status();
        }
    }
    IpcHandler {
        target: "airplane"

        function toggle(): void {
            Airplane.toggle();
        }
        function on(): void {
            Airplane.setOn(true);
        }
        function off(): void {
            Airplane.setOn(false);
        }
        function status(): string {
            return Airplane.on ? "on" : "off";
        }
    }
    IpcHandler {
        target: "hotspot"

        function status(): string {
            return Hotspot.on ? "on " + Hotspot.ssid : "off";
        }
        function off(): void {
            Hotspot.setOn(false);
        }
        function page(): void {
            ControlState.toggle("hotspot");
        }
    }

    // Tidy up after popups. Each one leaves JS garbage behind (search
    // results, rows, models) and the engine only collects it when it runs
    // short, so it piles up: ~40 MB after a few launcher opens. Collect once
    // everything has closed (measured: memory then stays flat).
    readonly property bool anyPopup: LauncherState.mapped || ClipboardState.mapped
        || ControlState.mapped || CalendarState.mapped || NowPlayingState.mapped || SysmonState.mapped
        || VolumeState.mapped || UpdatesState.mapped || CheatSheetState.mapped || SessionState.mapped
        || SwitcherState.mapped || Wallpaper.pickerMapped || Notifs.centerMapped
        || SettingsState.open || OverviewState.mapped
    // A popup opening before then cancels it: a collection in the middle of
    // its opening animation is a frame or two the animation doesn't get.
    onAnyPopupChanged: {
        if (anyPopup)
            tidy.stop();
        else
            tidy.restart();
    }
    Timer {
        id: tidy
        interval: 1500
        onTriggered: gc()
    }

    // The clipboard history: only exists while open. Reading
    // Clipboard.dryRun here starts its history keeping at startup.
    readonly property bool keepingClipboard: !Clipboard.dryRun
    Variants {
        model: Quickshell.screens

        Scope {
            id: clipboardScope
            required property ShellScreen modelData

            LazyLoader {
                active: ClipboardState.mapped

                ClipboardWindow {
                    modelData: clipboardScope.modelData
                }
            }
        }
    }

    // Super+V runs `mine clipboard`, which calls this.
    IpcHandler {
        id: clipboardIpc
        target: "clipboard"

        function toggle(): void {
            ClipboardState.toggle();
        }
        function close(): void {
            ClipboardState.close();
        }
    }

    // Dim, screen off and lock when idle (services/Idle.qml) run as long as
    // the shell does.
    readonly property bool idleWatching: !Idle.dryRun

    // qs -c mine ipc call idle keepAwake   (toggles "Keep awake")
    IpcHandler {
        target: "idle"

        function keepAwake(): void {
            Idle.keepAwake = !Idle.keepAwake;
        }
        // scripts/lock-guard.sh and scripts/shell-keeper.sh: is the shell
        // there and answering?
        function ping(): string {
            return "pong";
        }
    }

    // Locking before sleep and on request (services/Locker.qml) runs as
    // long as the shell does.
    readonly property bool lockingBeforeSleep: Locker.enabled

    // Reopening the apps of the last session at login, and keeping their
    // list (services/AppRestore.qml). Its "the system is going down" comes
    // from the Locker's logind listener (the shell has just the one).
    readonly property bool restoringApps: AppRestore.enabled
    Connections {
        target: Locker
        function onShutdown(going) {
            if (going)
                AppRestore.leave("shutdown");
            else
                AppRestore.stay();
        }
    }

    // Media keys: mango runs `mine key <action>`, which calls this.
    IpcHandler {
        id: keysIpc
        target: "keys"

        function volumeUp(): void {
            MediaKeys.volume(Style.keyVolumeStep);
        }
        function volumeDown(): void {
            MediaKeys.volume(-Style.keyVolumeStep);
        }
        function volumeMute(): void {
            MediaKeys.toggleMute();
        }
        function micMute(): void {
            MediaKeys.toggleMic();
        }
        function brightnessUp(): void {
            MediaKeys.brightness(Style.keyBrightnessStep);
        }
        function brightnessDown(): void {
            MediaKeys.brightness(-Style.keyBrightnessStep);
        }
        function playPause(): void {
            MediaKeys.player?.togglePlaying();
        }
        function next(): void {
            MediaKeys.player?.next();
        }
        function previous(): void {
            MediaKeys.player?.previous();
        }
    }

    // Auto brightness (services/AutoBrightness.qml): reading this starts it
    // (nothing runs while Style.autoBrightness is off).
    readonly property bool autoBrightnessOn: AutoBrightness.enabled

    // qs -c mine ipc call autobright on | off | toggle | forget | status
    // (status: JSON with the light, the target and what it learned.)
    IpcHandler {
        target: "autobright"

        function on(): void {
            AutoBrightness.setOn(true);
        }
        function off(): void {
            AutoBrightness.setOn(false);
        }
        function toggle(): void {
            AutoBrightness.toggle();
        }
        function forget(): void {
            AutoBrightness.forget();
        }
        function status(): string {
            return AutoBrightness.status();
        }
    }

    // Super (tap) runs `mine launcher`, which calls this.
    IpcHandler {
        id: launcherIpc
        target: "launcher"

        function toggle(): void {
            LauncherState.toggle();
        }
        function close(): void {
            LauncherState.close();
        }

        // App grid: `mine launcher grid` opens the launcher as a grid of
        // every app (again: closes it).
        function grid(): void {
            LauncherState.toggleGrid();
        }
    }

    // From a terminal: qs -c mine ipc call notifs toggle   (or clear / dnd)
    IpcHandler {
        target: "notifs"

        function toggle(): void {
            Notifs.setCenter(!Notifs.centerOpen);
        }
        function clear(): void {
            Notifs.clearAll();
        }
        function dnd(): void {
            Notifs.toggleDnd();
        }
    }

    // From a terminal: qs -c mine ipc call osd preview volume
    // (or mic / brightness / tiling), handy while tweaking the look.
    IpcHandler {
        target: "osd"

        function preview(kind: string): void {
            OsdState.show(kind);
        }
    }

    // The power menu (⏻ / Super+X). One window, on the screen mango picks.
    LazyLoader {
        active: SessionState.mapped

        SessionWindow {}
    }

    IpcHandler {
        id: sessionIpc
        target: "session"

        function toggle(): void {
            SessionState.toggle();
        }
        function close(): void {
            SessionState.close();
        }
    }

    // Restart to Windows (services/WindowsBoot.qml; also the power menu's
    // button while the firmware has a Windows Boot Manager entry).
    // qs -c mine ipc call winboot restart | status | check
    // (restart: the password dialog, then BootNext = Windows and a restart;
    // no second press: the password is the confirmation.)
    IpcHandler {
        target: "winboot"

        function restart(): void {
            SessionState.close();
            WindowsBoot.restart();
        }
        function status(): string {
            return WindowsBoot.status();
        }
        function check(): void {
            WindowsBoot.check();
        }
    }

    // The password dialog for admin rights. Reading PolkitService here
    // starts the polkit agent at startup (Noctalia's must be off: `mine on`).
    LazyLoader {
        active: PolkitService.mapped

        PolkitWindow {
            flow: PolkitService.flow
            active: PolkitService.active
        }
    }

    // ---- Wallpaper (step 6) ----------------------------------------------------
    // The wallpaper on every screen, and the picker (only while open).
    Variants {
        model: Quickshell.screens

        WallpaperWindow {}
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: pickerScope
            required property ShellScreen modelData

            LazyLoader {
                active: Wallpaper.pickerMapped

                PickerWindow {
                    modelData: pickerScope.modelData
                }
            }
        }
    }

    // The small wallpaper copy the frosted panels blur (power menu, cheat
    // sheet, Alt+Tab, OSD…): reading it here decodes it in the background
    // at start, so their first opening doesn't (common/SmallWallpaper.qml).
    readonly property bool smallWallpaper: SmallWallpaper.ready

    // The clock, the weather and the widget cards on the desktop
    // (Style.desktopClock, Style.desktopWidgets).
    Variants {
        model: Quickshell.screens

        Scope {
            id: desktopScope
            required property ShellScreen modelData

            LazyLoader {
                active: Style.desktopClock || Style.desktopWidgets.length > 0

                DesktopWindow {
                    modelData: desktopScope.modelData
                }
            }
        }
    }

    // Battery care (services/BatteryCare.qml): power saver when unplugged,
    // low battery warnings. Reading it here starts it with the shell.
    readonly property bool batteryCare: BatteryCare.loaded
    // UI sounds (services/Sounds.qml): made at start, so its quiet first
    // moment is over before the first click.
    readonly property bool sounds: Sounds.armed
    // The album cover's colors while music plays (services/ArtColors.qml).
    readonly property bool artColors: ArtColors.enabled
    // Headphones, mouse…: their batteries (services/Peripherals.qml), so the
    // low-battery notification works without the bar item too.
    readonly property int peripherals: Peripherals.devices.length
    // Your phone (KDE Connect, services/Phone.qml): asked once at start, so
    // the control center knows whether to show its tile.
    readonly property bool phoneInstalled: Phone.installed
    // Tailscale (services/Tailscale.qml): asked once at start, likewise.
    readonly property bool tailscaleInstalled: Tailscale.installed
    // Claude Code sessions done or waiting for you (services/Agents.qml).
    readonly property bool agentsWatching: Agents.watching

    // The focus timer (services/FocusTimer.qml, on the bar if added there).
    // qs -c mine ipc call focus toggle | reset | skip
    IpcHandler {
        target: "focus"

        function toggle(): void {
            FocusTimer.toggle();
        }
        function reset(): void {
            FocusTimer.reset();
        }
        function skip(): void {
            FocusTimer.skip();
        }
    }

    // Package updates (services/Updates.qml, the bar's "updates" item).
    // qs -c mine ipc call updates check | run | panel | status
    // (run: the update command in a terminal; panel: the updates panel;
    // `done` is what the update terminal, or the panel's install, says when
    // it ends.)
    IpcHandler {
        target: "updates"

        function check(): void {
            Updates.check("ipc");
        }
        function run(): void {
            Updates.run();
        }
        function panel(): void {
            UpdatesState.request();
        }
        function done(): void {
            Updates.done();
        }
        function status(): string {
            const install = UpdateRun.describe();
            return (Updates.checking ? "checking"
                : Updates.count + " (" + (Updates.summary || "none") + "), checked " + Updates.ago(Updates.checkedAt)
                  + (Updates.failed !== "" ? "; " + Updates.failed : "")
                  + (Updates.headsUp.length > 0 ? "; heads-up: " + Updates.headsUp.join(" ") : ""))
                + (install !== "" ? "; install " + install : "");
        }
    }

    // The panel's install (services/UpdateRun.qml): reading this starts it
    // with the shell, so an install still going on (or just finished) while
    // the shell restarted is picked back up at once.
    readonly property bool updateRunWatching: UpdateRun.loaded
    // The password dialog is up: the updates panel lets it have the keyboard.
    Binding {
        target: UpdatesState
        property: "passwordUp"
        value: PolkitService.active
    }

    // Night light (services/NightLight.qml): reading it here starts wlsunset
    // with the shell when it's on.
    readonly property bool nightLightOn: NightLight.isOn

    // qs -c mine ipc call nightlight toggle | cycle | set off|on|schedule
    IpcHandler {
        target: "nightlight"

        function toggle(): void {
            NightLight.toggle();
        }
        function cycle(): void {
            NightLight.cycle();
        }
        function set(mode: string): void {
            NightLight.setMode(mode);
        }
    }

    // qs -c mine ipc call theme toggle | auto | set dark|light|auto | get
    IpcHandler {
        target: "theme"

        function toggle(): void {
            Theme.toggle();
        }
        function auto(): void {
            Theme.setMode("auto");
        }
        function set(mode: string): void {
            Theme.setMode(mode);
        }
        function get(): string {
            return Theme.mode + " (" + (Theme.dark ? "dark" : "light") + ")";
        }
    }

    // qs -c mine ipc call wallpaper toggle | set <path> | next | random | get
    IpcHandler {
        id: wallpaperIpc
        target: "wallpaper"

        function toggle(): void {
            Wallpaper.togglePicker();
        }
        function set(path: string): void {
            Wallpaper.set(path);
        }
        function next(): void {
            Wallpaper.next();
        }
        function random(): void {
            Wallpaper.random();
        }
        function get(): string {
            return Wallpaper.current;
        }
    }

    // Screenshots: the overlay only exists while you pick (Print /
    // Super+Shift+S); Ctrl+Print never shows it.
    LazyLoader {
        active: Screenshot.active

        ShotWindow {}
    }

    // qs -c mine ipc call screenshot region | window | screen | text | close
    // (text: copy the words in a region, Super+Shift+T)
    // … screenshot edit <file.png>: mark up a saved screenshot (the
    // notification's Edit); prints "ok", or why not (then use swappy).
    IpcHandler {
        id: screenshotIpc
        target: "screenshot"

        function region(): void {
            Screenshot.region();
        }
        function window(): void {
            Screenshot.window();
        }
        function screen(): void {
            Screenshot.screen();
        }
        function text(): void {
            Screenshot.text();
        }
        function close(): void {
            Screenshot.close();
        }
        function edit(file: string): string {
            return Screenshot.editSaved(file);
        }
        // The overlay on a tool: scan a QR code or barcode, search with
        // Google Lens, translate the text (services/Screenshot.qml).
        function qr(): void {
            Screenshot.qr();
        }
        function lens(): void {
            Screenshot.lens();
        }
        function translate(): void {
            Screenshot.translate();
        }
    }

    // Screen recording (services/Recorder.qml): Super+Shift+R / Super+Alt+R
    // run `mine record screen|region`; either one stops a recording.
    // qs -c mine ipc call record toggle | screen | region | stop
    IpcHandler {
        id: recordIpc
        target: "record"

        function toggle(): void {
            Recorder.toggle();
        }
        function screen(): void {
            Recorder.start("screen");
        }
        function region(): void {
            Recorder.start("region");
        }
        function stop(): void {
            Recorder.stop();
        }
    }

    // Color picker (services/ColorPicker.qml): Super+Shift+C runs
    // `mine picker`. qs -c mine ipc call picker pick
    IpcHandler {
        id: pickerIpc
        target: "picker"

        function pick(): void {
            ColorPicker.pick();
        }
    }

    // The calendar (click the clock): only exists while open. Reading
    // Weather.enabled here starts the weather updates with the shell.
    readonly property bool weatherUpdating: Weather.enabled
    Variants {
        model: Quickshell.screens

        Scope {
            id: calendarScope
            required property ShellScreen modelData

            LazyLoader {
                active: CalendarState.mapped

                CalendarWindow {
                    modelData: calendarScope.modelData
                }
            }
        }
    }

    // qs -c mine ipc call calendar toggle | close
    IpcHandler {
        target: "calendar"

        function toggle(): void {
            CalendarState.toggle();
        }
        function close(): void {
            CalendarState.close();
        }
    }

    // The Now Playing card (click the song): only exists while open.
    Variants {
        model: Quickshell.screens

        Scope {
            id: nowPlayingScope
            required property ShellScreen modelData

            LazyLoader {
                active: NowPlayingState.mapped

                NowPlayingWindow {
                    modelData: nowPlayingScope.modelData
                }
            }
        }
    }

    // qs -c mine ipc call nowplaying toggle | open | close
    IpcHandler {
        target: "nowplaying"

        function toggle(): void {
            NowPlayingState.toggle();
        }
        function open(): void {
            NowPlayingState.show();
        }
        function close(): void {
            NowPlayingState.close();
        }
    }

    // Lyrics: the card's on/off (toggle), the bar's line (bar), look the
    // song up again (reload), what it has (status).
    IpcHandler {
        target: "lyrics"

        function toggle(): void {
            Settings.set("lyricsInCard", !Style.lyricsInCard);
        }
        function bar(): void {
            Settings.set("lyricsInBar", !Style.lyricsInBar);
        }
        function reload(): void {
            Lyrics.reload();
        }
        function status(): string {
            return Lyrics.describe();
        }
    }

    // The System popup (click a stat on the bar): only exists while open.
    Variants {
        model: Quickshell.screens

        Scope {
            id: sysmonScope
            required property ShellScreen modelData

            LazyLoader {
                active: SysmonState.mapped

                SysmonWindow {
                    modelData: sysmonScope.modelData
                }
            }
        }
    }

    // qs -c mine ipc call sysmon toggle | close
    IpcHandler {
        target: "sysmon"

        function toggle(): void {
            SysmonState.toggle();
        }
        function close(): void {
            SysmonState.close();
        }
    }

    // Alt+Tab window switcher: only exists while open (on the focused screen).
    LazyLoader {
        active: SwitcherState.mapped

        SwitcherWindow {}
    }

    // Alt+Tab / Alt+Shift+Tab run `mine switcher next|previous`, which call this.
    IpcHandler {
        id: switcherIpc
        target: "switcher"

        function next(): void {
            SwitcherState.next();
        }
        function previous(): void {
            SwitcherState.previous();
        }
        function close(): void {
            SwitcherState.cancel();
        }
    }

    // The Settings window: only exists while open (Super+, / ⚙).
    LazyLoader {
        active: SettingsState.open

        SettingsWindow {}
    }

    // qs -c mine ipc call settings open | close | toggle
    IpcHandler {
        target: "settings"

        function open(): void {
            SettingsState.show();
        }
        function close(): void {
            SettingsState.close();
        }
        function toggle(): void {
            SettingsState.toggle();
        }
    }

    // The shortcut cheat sheet: only exists while open (Super+/).
    LazyLoader {
        active: CheatSheetState.mapped

        CheatSheetWindow {}
    }

    // Super+/ runs `mine cheatsheet`, which calls this.
    // qs -c mine ipc call cheatsheet toggle | open | close
    IpcHandler {
        id: cheatsheetIpc
        target: "cheatsheet"

        function toggle(): void {
            CheatSheetState.toggle();
        }
        function open(): void {
            CheatSheetState.show();
        }
        function close(): void {
            CheatSheetState.close();
        }
    }

    // The overview: only exists while open (on the focused screen).
    LazyLoader {
        active: OverviewState.mapped

        OverviewWindow {}
    }

    // The hot corner (Style.overviewHotCorner) lives in the bar's window
    // (top corners) or the dock's (bottom corners): overview/HotCorner.qml.

    // Super+O (and 4 fingers up) run `mine overview`, which calls this.
    // qs -c mine ipc call overview toggle | open | close
    IpcHandler {
        id: overviewIpc
        target: "overview"

        function toggle(): void {
            OverviewState.toggle();
        }
        function open(): void {
            OverviewState.show();
        }
        function close(): void {
            OverviewState.close();
        }
    }

    // The on-screen keyboard: only exists while it shows. It comes up when
    // the screen folds back into a tablet (mango's switchbind runs
    // `mine osk fold`), or from the bar's keyboard item.
    LazyLoader {
        active: OskState.mapped

        OskWindow {}
    }

    // qs -c mine ipc call osk toggle | open | close | tablet | fold | unfold
    // (tablet: up if the screen is folded back now, away if not, as
    // $XDG_RUNTIME_DIR/mine-tablet says; fold / unfold: from mango's
    // switchbind, through `mine`. Not "show": `qs ipc call osk show` would
    // list the target instead.)
    IpcHandler {
        id: oskIpc
        target: "osk"

        function toggle(): void {
            OskState.toggle();
        }
        function open(): void {
            OskState.show();
        }
        function close(): void {
            OskState.hide();
        }
        function tablet(): void {
            OskState.tablet();
        }
        function fold(): void {
            OskState.fold();
        }
        function unfold(): void {
            OskState.unfold();
        }
    }

    // Turning the screen with the tablet (services/AutoRotate.qml): reading
    // this starts it (nothing runs while Style.rotateScreen is "off").
    readonly property bool rotating: AutoRotate.active
    // Nothing is turned while Idle has the screen off: mango would wake it.
    Binding {
        target: AutoRotate
        property: "screenOff"
        value: Idle.screenOff
    }

    // qs -c mine ipc call rotate lock | unlock | toggle | status
    // (lock: the screen stays as it is until unlock; status: JSON.)
    IpcHandler {
        target: "rotate"

        function lock(): void {
            AutoRotate.lock();
        }
        function unlock(): void {
            AutoRotate.unlock();
        }
        function toggle(): void {
            AutoRotate.toggleLock();
        }
        function status(): string {
            return AutoRotate.status();
        }
    }

    // ---- Screen time, break reminders, AI usage -------------------------------------
    // Screen time and the break reminders (services/ScreenTime.qml,
    // services/Breaks.qml): reading these starts them with the shell (no bar
    // item needed). Screen off comes from Idle; what's counted is saved when
    // the system goes down and when the power menu locks, sleeps or leaves.
    // AI usage (services/AiUsage.qml) only checks while its bar item or
    // popup is there.
    readonly property bool screenTimeOn: ScreenTime.watching
    readonly property bool breaksOn: Breaks.watching
    Binding {
        target: ScreenTime
        property: "screenOff"
        value: Idle.screenOff
    }
    Connections {
        target: Locker
        function onShutdown(going) {
            if (going)
                ScreenTime.flush("shutdown");
        }
    }
    Connections {
        target: SessionState
        function onPendingChanged() {
            if (SessionState.pending)
                ScreenTime.flush("power menu");
        }
    }
    // "Take a break": the countdown on every screen, only while it's on.
    Variants {
        model: Quickshell.screens

        Scope {
            id: breakScope
            required property ShellScreen modelData

            LazyLoader {
                active: Breaks.showing

                BreakWindow {
                    modelData: breakScope.modelData
                }
            }
        }
    }

    // qs -c mine ipc call screentime popup | status | breaks | breakNow | skip | reminders on|off|toggle | save
    // (status: JSON with today per app and the last 7 days, in seconds;
    // breaks: the reminders' state.)
    IpcHandler {
        id: screentimeIpc
        target: "screentime"

        function popup(): void {
            BarPopupState.toggle("screentime", "", Qt.rect(0, 0, 0, 0));
        }
        function status(): string {
            return ScreenTime.status();
        }
        function breaks(): string {
            return Breaks.status();
        }
        function breakNow(): void {
            Breaks.takeBreak();
        }
        function skip(): void {
            Breaks.skipBreak();
        }
        function reminders(on: string): void {
            Breaks.setOn(on === "toggle" ? !Breaks.enabled : on === "on");
        }
        function save(): void {
            ScreenTime.flush("ipc");
        }
    }

    // qs -c mine ipc call aiusage popup | status | refresh
    // (status: JSON with the percentages and reset times only.)
    IpcHandler {
        id: aiusageIpc
        target: "aiusage"

        function popup(): void {
            BarPopupState.toggle("aiusage", "", Qt.rect(0, 0, 0, 0));
        }
        function status(): string {
            return AiUsage.status();
        }
        function refresh(): void {
            AiUsage.refresh();
        }
    }

    // ---- Timer, stopwatch, alarms (services/Timers.qml) -------------------------
    // Read at start, so alarms ring without the control center ever opening.
    readonly property bool timersLoaded: Timers.loaded

    // qs -c mine ipc call timers start <length> | pause | cancel | stop | snooze
    //   | stopwatch | lap | reset | alarm "<HH:MM> [label]" | page timer|stopwatch|alarms | status
    // (length: 5 (minutes), 1:30, 1h 20m; stop / snooze: the one ringing;
    // alarm: a new one, once; page: the control center on that tab; status: JSON.)
    IpcHandler {
        id: timersIpc
        target: "timers"

        function start(length: string): string {
            return Timers.startTimer(Timers.parseLength(length)) ? "ok" : "not a length: try 5, 1:30 or 1h 20m";
        }
        function pause(): void {
            Timers.toggleTimer();
        }
        function cancel(): void {
            Timers.cancelTimer();
        }
        function stop(): void {
            Timers.stopRing();
        }
        function snooze(): void {
            Timers.snooze();
        }
        function stopwatch(): void {
            Timers.toggleStopwatch();
        }
        function lap(): void {
            Timers.lap();
        }
        function reset(): void {
            Timers.resetStopwatch();
        }
        function alarm(spec: string): string {
            const m = spec.trim().match(/^(\d{1,2}:\d{2})\s*(.*)$/);
            return m && Timers.addAlarm(m[1], [], m[2]) !== "" ? "ok" : "not a time: try 07:00 or \"07:00 Wake up\"";
        }
        function page(tab: string): void {
            Timers.pageTab = ["timer", "stopwatch", "alarms"].includes(tab) ? tab : "timer";
            ControlState.show("timers");
        }
        function status(): string {
            return Timers.status();
        }
    }

    // ---- Drawing on the screen (services/Ink.qml) --------------------------------
    // One see-through window per screen, only while the ink is on.
    Variants {
        model: Quickshell.screens

        Scope {
            id: inkScope
            required property ShellScreen modelData

            LazyLoader {
                active: Ink.open

                InkWindow {
                    modelData: inkScope.modelData
                }
            }
        }
    }

    // qs -c mine ipc call ink toggle | open | close | clear | undo | passthrough | save
    IpcHandler {
        id: inkIpc
        target: "ink"

        function toggle(): void {
            Ink.toggle();
        }
        function open(): void {
            Ink.show();
        }
        function close(): void {
            Ink.close();
        }
        function clear(): void {
            Ink.clear();
        }
        function undo(): void {
            Ink.undo();
        }
        function passthrough(): void {
            Ink.togglePassThrough();
        }
        function save(): void {
            Ink.save();
        }
    }

    // ---- Notes and to-dos (services/Notes.qml) -----------------------------------
    // The panel: only exists while open (or fading out).
    LazyLoader {
        active: Notes.mapped

        NotesWindow {}
    }

    // qs -c mine ipc call notes toggle | open | close | add text|list|ink
    IpcHandler {
        id: notesIpc
        target: "notes"

        function toggle(): void {
            Notes.toggle();
        }
        function open(): void {
            Notes.show();
        }
        function close(): void {
            Notes.close();
        }
        // A new note of that kind, open in the panel.
        function add(kind: string): void {
            Notes.show(Notes.add(kind));
        }
    }

    // ---- Key binds' quick way in -------------------------------------------------
    // mango's key binds run ~/.local/bin/mine, which used to start a whole
    // `qs ipc` client for every key: ~80 ms before the shell even heard of
    // it (Super, Alt+Tab, every volume key repeat). Now mine writes one line,
    // "<target> <function> [argument]", to this socket (socat, ~5 ms), and
    // the shell calls that IpcHandler above, like `qs ipc call` would. The
    // answer is "ok", or "no" (no such handler or function), and then mine
    // still tries `qs ipc` as before. Only the user can reach the socket
    // ($XDG_RUNTIME_DIR), the same as `qs ipc`; a file left by a crash is
    // replaced when the shell starts again. MINE_IPC_SOCKET: tests.
    readonly property string ipcSocket: Quickshell.env("MINE_IPC_SOCKET")
        || `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/qs-${Quickshell.shellDir.replace(/\/+$/, "").split("/").pop()}.sock`

    // The handlers key binds use (ShellRoot's children can't be walked from JS).
    readonly property list<IpcHandler> quickHandlers: [launcherIpc, controlIpc, sessionIpc, wallpaperIpc,
        clipboardIpc, overviewIpc, cheatsheetIpc, pickerIpc, switcherIpc, keysIpc, screenshotIpc, recordIpc, oskIpc,
        inkIpc, notesIpc, timersIpc, screentimeIpc, aiusageIpc]

    // Only a function the handler itself declares, like `qs ipc` allows:
    // not one every object has (destroy, toString…) nor a change signal.
    readonly property var notCallable: ["destroy", "deleteLater", "toString", "valueOf", "constructor", "connect",
        "disconnect", "hasOwnProperty", "isPrototypeOf", "propertyIsEnumerable", "toLocaleString"]
    function quickCall(line: string): bool {
        const [target, fn, ...rest] = line.trim().split(/\s+/);
        if (!target || !fn || !/^[a-z][A-Za-z0-9]*$/.test(fn) || /Changed$/.test(fn) || shell.notCallable.includes(fn))
            return false;
        for (const handler of shell.quickHandlers) {
            if (handler.target !== target || typeof handler[fn] !== "function")
                continue;
            // A call that throws still counts as heard: mine must not run
            // it a second time through qs ipc.
            try {
                if (rest.length > 0)
                    handler[fn](rest.join(" "));
                else
                    handler[fn]();
            } catch (e) {
                console.warn("ipc:", line.trim(), "failed:", e);
            }
            return true;
        }
        return false;
    }

    SocketServer {
        active: true
        path: shell.ipcSocket

        handler: Socket {
            id: caller

            parser: SplitParser {
                onRead: line => {
                    caller.write(shell.quickCall(line) ? "ok\n" : "no\n");
                    caller.flush();
                    caller.connected = false;
                }
            }
        }
    }
}
