import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The wallpaper on one screen: the background layer under everything.
// mango must not blur behind it (nothing is there): see
// `layer_rule=no_blur:1,layer_name:^mine-wallpaper$` in shell-noctalia.conf.
PanelWindow {
    id: root

    required property ShellScreen modelData

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    // Until the picture is there (a moment at login): the theme's dark
    // surface, the same as mango's root_color and the login screen's last
    // color, so the picture fades in out of it (common/Intro.qml).
    color: Colors.surface

    WlrLayershell.namespace: "mine-wallpaper"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    WallpaperView {
        anchors.fill: parent
        source: Wallpaper.current
        origin: Wallpaper.origin
        // Decode at the real pixel size of the screen, no bigger (the
        // window's own ratio, 1.25 here: Screen's is the whole-number
        // output scale, 2, which decoded 2.56× the pixels).
        decodeSize: Qt.size(Math.ceil(root.width * root.devicePixelRatio), Math.ceil(root.height * root.devicePixelRatio))
    }
}
