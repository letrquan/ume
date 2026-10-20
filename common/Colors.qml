pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Material colors of the current wallpaper, for everything in the shell.
// services/Wallpaper.qml asks matugen for them whenever the wallpaper
// changes and writes ~/.local/state/mine-shell/colors.json; this file reads
// it live, so the colors glide to the new ones (no shell reload). The
// values written here are only used until that file exists.
// Names: Material roles, with on_* as textOn* (QML can't have onX names).
Singleton {
    id: root

    readonly property string path: Quickshell.env("MINE_COLORS_JSON")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/colors.json")
    readonly property int fade: Style.wallpaperReveal
    property var c: ({})
    // The first palette (at start) applies at once: animating from the
    // built-in fallbacks would tint everything mid-way through the way in
    // (Intro). Later ones (a new wallpaper, album art) fade.
    property bool ready: false
    // While music plays, services/ArtColors.qml puts the album cover's
    // colors here (only the roles it sets; the others stay the wallpaper's).
    // Only the shell itself: the files Wallpaper.qml writes (GTK, mango,
    // foot, the lock) always get the wallpaper's.
    property var art: ({})
    readonly property var v: Object.assign({}, c, art)

    readonly property string wallpaper: c.wallpaper ?? ""
    property color primary: v.primary ?? "#aacbe0"
    Behavior on primary { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color textOnPrimary: v.textOnPrimary ?? "#113445"
    Behavior on textOnPrimary { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color primaryContainer: v.primaryContainer ?? "#59798c"
    Behavior on primaryContainer { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color textOnPrimaryContainer: v.textOnPrimaryContainer ?? "#fcfdff"
    Behavior on textOnPrimaryContainer { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color secondary: v.secondary ?? "#bcc8d1"
    Behavior on secondary { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color textOnSecondary: v.textOnSecondary ?? "#263239"
    Behavior on textOnSecondary { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color secondaryContainer: v.secondaryContainer ?? "#3f4b52"
    Behavior on secondaryContainer { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color textOnSecondaryContainer: v.textOnSecondaryContainer ?? "#aebac3"
    Behavior on textOnSecondaryContainer { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color tertiary: v.tertiary ?? "#d9bee0"
    Behavior on tertiary { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color textOnTertiary: v.textOnTertiary ?? "#3c2944"
    Behavior on textOnTertiary { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color tertiaryContainer: v.tertiaryContainer ?? "#846d8c"
    Behavior on tertiaryContainer { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color textOnTertiaryContainer: v.textOnTertiaryContainer ?? "#fffcff"
    Behavior on textOnTertiaryContainer { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color error: v.error ?? "#ffb4ab"
    Behavior on error { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color textOnError: v.textOnError ?? "#690005"
    Behavior on textOnError { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color errorContainer: v.errorContainer ?? "#93000a"
    Behavior on errorContainer { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color textOnErrorContainer: v.textOnErrorContainer ?? "#ffdad6"
    Behavior on textOnErrorContainer { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color surface: v.surface ?? "#121415"
    Behavior on surface { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color textOnSurface: v.textOnSurface ?? "#e3e2e4"
    Behavior on textOnSurface { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color surfaceVariant: v.surfaceVariant ?? "#42474c"
    Behavior on surfaceVariant { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color textOnSurfaceVariant: v.textOnSurfaceVariant ?? "#c2c7cc"
    Behavior on textOnSurfaceVariant { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color surfaceContainerLowest: v.surfaceContainerLowest ?? "#0d0e10"
    Behavior on surfaceContainerLowest { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color surfaceContainerLow: v.surfaceContainerLow ?? "#1a1c1d"
    Behavior on surfaceContainerLow { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color surfaceContainer: v.surfaceContainer ?? "#1e2021"
    Behavior on surfaceContainer { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color surfaceContainerHigh: v.surfaceContainerHigh ?? "#292a2b"
    Behavior on surfaceContainerHigh { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color surfaceContainerHighest: v.surfaceContainerHighest ?? "#333536"
    Behavior on surfaceContainerHighest { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color outline: v.outline ?? "#8c9196"
    Behavior on outline { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color outlineVariant: v.outlineVariant ?? "#42474c"
    Behavior on outlineVariant { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color shadow: v.shadow ?? "#000000"
    Behavior on shadow { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color scrim: v.scrim ?? "#000000"
    Behavior on scrim { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color inverseSurface: v.inverseSurface ?? "#e3e2e4"
    Behavior on inverseSurface { enabled: root.ready; ColorAnimation { duration: root.fade } }
    property color inverseOnSurface: v.inverseOnSurface ?? "#2f3032"
    Behavior on inverseOnSurface { enabled: root.ready; ColorAnimation { duration: root.fade } }

    FileView {
        path: root.path
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: {
            try {
                root.c = JSON.parse(text());
            } catch (e) {
                console.warn("colors: can't read", root.path);
            }
            if (!root.ready)
                Qt.callLater(() => root.ready = true);
        }
        onLoadFailed: if (!root.ready) root.ready = true
    }
}
