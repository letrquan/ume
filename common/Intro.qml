pragma Singleton
import QtQuick
import Quickshell

// The shell's way in, once per start (a fresh login or `mine restart`):
// the wallpaper fades in from the theme's dark surface (the color mango
// shows, root_color, and the color the login screen dims to), then the bar's
// islands drop in, the dock rises and the desktop clock fades in, in that
// order. One fade through dark from the login screen to the desktop, no
// pops. Style.startupIntro off: everything is simply there.
Singleton {
    id: root

    readonly property bool enabled: Style.startupIntro
    // How long the wallpaper takes to fade in.
    readonly property int wallpaperFade: enabled ? 700 : 0
    // When the rest comes in (Island, DockView, DesktopWindow wait for it):
    // a little after a wallpaper starts fading in, or after a safety
    // timeout if no picture ever loads. Right away with the intro off.
    property bool started: !enabled

    // WallpaperView: its first picture is decoded and fading in.
    function wallpaperShown() {
        if (!started && !go.running)
            go.start();
    }

    Timer {
        id: go
        interval: root.wallpaperFade * 0.45
        onTriggered: root.started = true
    }
    Timer {
        interval: 2500
        running: !root.started
        onTriggered: root.started = true
    }
}
