pragma Singleton
import QtQuick
import Quickshell

// The bar's MangoMonitor of each screen (bar/BarContent.qml puts it here),
// so the dock reads the same one instead of running a second
// `mmsg watch monitor <name>`.
//
// It also says where a panel opens. The launcher, the control center, the
// clipboard, the wallpaper picker, the calendar, the Now Playing card and the
// System popup each exist on one screen while open: a copy on every screen
// would show them twice and have the copies compete for the keyboard. Each
// one calls panelScreen() when it opens and stays there until it's gone. The
// answer comes from what those monitors already know, so opening never waits
// and runs nothing new.
Singleton {
    id: root

    // { "<screen name>": MangoMonitor }
    property var byScreen: ({})

    function register(name, monitor) {
        const m = Object.assign({}, byScreen);
        if (monitor)
            m[name] = monitor;
        else
            delete m[name];
        byScreen = m;
    }

    // The screen a panel opens on: `want` (a bar item's own screen, see
    // screenOf), else the one with mango's focus, else the first one. Only
    // "" with no screens at all.
    function panelScreen(want) {
        const all = Quickshell.screens;
        if (all.length === 1)
            return all[0].name;
        if (want && all.some(s => s.name === want))
            return want;
        return (all.find(s => root.byScreen[s.name]?.focused) ?? all[0])?.name ?? "";
    }

    // The screen of the window an item is in.
    function screenOf(item) {
        return item.QsWindow.window?.screen?.name ?? "";
    }

    // The screen of an open panel went away: it carries on on another one (no
    // window would mean no way to click it or type in it, and it would stay
    // open). One that's closing has its timer and just goes.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            const here = name => Quickshell.screens.some(s => s.name === name);
            for (const p of [LauncherState, ControlState, ClipboardState, CalendarState, NowPlayingState, SysmonState]) {
                if (p.open && !here(p.screen))
                    p.screen = root.panelScreen();
            }
            if (Wallpaper.pickerOpen && !here(Wallpaper.pickerScreen))
                Wallpaper.pickerScreen = root.panelScreen();
        }
    }

    // While a panel is open, the screens it isn't on: a click on one closes it
    // (shell.qml), as a click outside it does on its own screen. Those windows
    // come a moment after the panel: made together, they cost its opening
    // animation a frame or two.
    readonly property var panelFreeScreens: {
        const all = Quickshell.screens;
        if (all.length < 2)
            return [];
        const on = [LauncherState, ControlState, ClipboardState, CalendarState, NowPlayingState, SysmonState]
            .filter(p => p.open).map(p => p.screen);
        if (Wallpaper.pickerOpen)
            on.push(Wallpaper.pickerScreen);
        return on.length > 0 ? all.filter(s => !on.includes(s.name)) : [];
    }
    property var clickAwayScreens: []
    onPanelFreeScreensChanged: {
        if (panelFreeScreens.length === 0) {
            clickAwayDelay.stop();
            clickAwayScreens = [];
        } else {
            clickAwayDelay.restart();
        }
    }
    Timer {
        id: clickAwayDelay
        interval: 200
        onTriggered: root.clickAwayScreens = root.panelFreeScreens
    }

    function closePanels() {
        LauncherState.close();
        ControlState.close();
        ClipboardState.close();
        CalendarState.close();
        NowPlayingState.close();
        SysmonState.close();
        if (Wallpaper.pickerOpen)
            Wallpaper.setPicker(false);
    }
}
