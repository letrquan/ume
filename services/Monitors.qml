pragma Singleton
import QtQuick
import Quickshell
import qs.common

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
    // screenOf), else `stay` (the one it's still shrinking back on), else the
    // one with mango's focus, else the first one. Each only if it's still
    // there; only "" with no screens at all. A new answer for a panel still
    // on another screen moves its window, so it has to be open by then.
    function panelScreen(want, stay) {
        const all = Quickshell.screens;
        if (all.length === 1)
            return all[0].name;
        for (const name of [want, stay]) {
            if (name && all.some(s => s.name === name))
                return name;
        }
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
    // (shell.qml), as a click outside it does on its own screen. Their windows
    // only take clicks while their screen is on this list. They come a moment
    // after the panel (made together, they cost its opening animation a frame
    // or two) and go once it has closed (letting go of a window stalls the
    // shell for a moment); a screen that's gone takes its window along at once.
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
        clickAwayScreens = clickAwayScreens.filter(s => Quickshell.screens.includes(s));
        clickAwayDelay.interval = panelFreeScreens.length > 0 ? 200 : Motion.morphOut + Motion.contentIn + 80;
        clickAwayDelay.restart();
    }
    Timer {
        id: clickAwayDelay
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
