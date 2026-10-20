pragma Singleton
import QtQuick
import Quickshell
import qs.common

// Light or dark (Style.themeMode):
//   "dark"   always (the default: nothing outside the shell is touched)
//   "light"  always
//   "auto"   light from sunrise to sunset at the weather place (Open-Meteo;
//            06:00-18:00 until it's known), dark at night
// The shell's colors follow (Wallpaper.qml asks matugen for the light or
// dark set; the lock, mango's borders, foot and the GTK colors too), and so
// do apps that follow the system's light/dark preference (libadwaita/GTK 4,
// browsers, Electron): that's GNOME's color-scheme setting, which GNOME
// shares, so it's only changed when light/dark actually changes here, or at
// start when the mode isn't plain "dark".
//
// MINE_THEME_DRYRUN=1 (tests): only prints the gsettings command.
Singleton {
    id: root

    readonly property string mode: Style.themeMode
    readonly property bool dark: mode === "dark" || (mode === "auto" && !daytime)
    readonly property bool dryRun: Quickshell.env("MINE_THEME_DRYRUN") === "1"

    // Between sunrise and sunset (checked every minute while on "auto").
    property bool daytime: isDay(new Date())

    function isDay(now) {
        const sun = Weather.sunTimes();
        if (!sun) {
            const h = now.getHours();
            return h >= 6 && h < 18;
        }
        return now.getTime() >= sun.rise && now.getTime() < sun.set;
    }
    Timer {
        interval: 60000
        running: root.mode === "auto"
        repeat: true
        triggeredOnStart: true
        onTriggered: root.daytime = root.isDay(new Date())
    }
    // Today's sunrise and sunset arrive with the weather.
    Connections {
        target: Weather
        function onDataChanged() {
            root.daytime = root.isDay(new Date());
        }
    }

    // Click: dark <-> light (from "auto": the other one of what shows now).
    function toggle() {
        setMode(dark ? "light" : "dark");
    }
    // Right click: "auto", or back to what shows now.
    function cycleAuto() {
        setMode(mode === "auto" ? (dark ? "dark" : "light") : "auto");
    }
    function setMode(m) {
        if (m === "dark")
            Settings.reset("themeMode");        // the default
        else if (m === "light" || m === "auto")
            Settings.set("themeMode", m);
    }

    // ---- Apps (GNOME's color-scheme) --------------------------------------------------
    property string applied: ""             // what this run last set

    function applyScheme(atStart) {
        const want = dark ? "prefer-dark" : "prefer-light";
        if (atStart && mode === "dark")
            return;                         // the default: leave GNOME's setting alone
        if (applied === want)
            return;
        applied = want;
        const cmd = ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", want];
        if (dryRun)
            console.log("theme (dry run):", cmd.join(" "));
        else
            Quickshell.execDetached(cmd);
    }
    // Changes while the bindings settle at start don't count.
    property bool ready: false
    onDarkChanged: if (ready) applyScheme(false)
    Component.onCompleted: {
        ready = true;
        applyScheme(true);
    }
}
