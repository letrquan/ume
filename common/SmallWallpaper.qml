pragma Singleton
import QtQuick
import Quickshell

// The small copy of the wallpaper that Backdrop and WallpaperFrost blur
// (the power menu, the cheat sheet, Alt+Tab, the OSD, the password dialog,
// the notification list), decoded once and kept, so opening one of those
// is a hit in Qt's picture cache instead of a fresh decode of the big file
// on the shell's main thread: ~180 ms for a 3840×2880 progressive JPEG,
// right when the window should start moving. Qt only keeps a picture
// nobody shows for ~30 s, hence this keeper (~1 MB). It decodes in the
// background when the wallpaper changes. shell.qml reads `ready` at start,
// so the first opening already finds it.
//
// Same file, size and fill as theirs (that's the cache's key): use
// `source` and `size` from here.
Singleton {
    id: root

    readonly property string source: Colors.wallpaper !== "" ? "file://" + Colors.wallpaper : ""
    // Fixed, not the window's: a window is 0 wide on its first frame.
    readonly property size size: Qt.size(Style.backdropDecodeWidth, 0)
    readonly property bool ready: keeper.status === Image.Ready

    Image {
        id: keeper
        source: root.source
        sourceSize: root.size
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
    }
}
