pragma Singleton
import QtQuick
import Quickshell

// Shared between the bar and what grows out of its islands (the
// notification island, the launcher, the clipboard, the calendar, the Now
// Playing card and the wallpaper picker from the middle one, the control center from the right one, the System popup
// from any of the three): how wide those
// islands are right now, and whether something stands in for them. Each
// owner has its own flag, so one closing never gives an island back under
// another.
Singleton {
    property real centerWidth: 200
    property bool notifCovering: false
    property bool launcherCovering: false
    property bool clipboardCovering: false
    property bool calendarCovering: false
    property bool pickerCovering: false
    // A live activity (services/Activities.qml) grown out of the island.
    property bool activityCovering: false
    // The Now Playing card (click the song).
    property bool nowPlayingCovering: false
    readonly property bool takenOver: notifCovering || launcherCovering || clipboardCovering || calendarCovering || pickerCovering || activityCovering || nowPlayingCovering

    // takenOver, on one screen's bar: a panel stands in for the island only on
    // the screen it opened on (Monitors.panelScreen); notifications and live
    // activities show on every screen.
    function takenOverOn(screenName) {
        return notifCovering || activityCovering
            || (launcherCovering && LauncherState.screen === screenName)
            || (clipboardCovering && ClipboardState.screen === screenName)
            || (calendarCovering && CalendarState.screen === screenName)
            || (pickerCovering && Wallpaper.pickerScreen === screenName)
            || (nowPlayingCovering && NowPlayingState.screen === screenName);
    }

    property real rightWidth: 300
    property bool controlCovering: false

    // The System popup (click a stat on the bar) grows out of whichever
    // island holds the stat: this one is hidden while it covers it.
    property real leftWidth: 200
    property bool sysmonCovering: false
    property string sysmonIsland: "right"   // left | center | right
}
