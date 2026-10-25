import QtQuick
import QtQuick.Effects

// The blurred wallpaper and the dim behind the power menu, the shortcut
// cheat sheet and the password dialog, drawn by the shell so they fade in
// and out together.
//
// mango used to blur these windows itself, but it blurs every pixel that
// isn't fully transparent at full strength and can't fade that: the first
// frame of a fading dim already turned the whole screen into blurred
// wallpaper (blur_optimized shows the wallpaper, not your windows), and it
// stayed until the last frame of the fade out. Here it's the same picture
// (the wallpaper, blurred, a little darker and richer, like mango's
// blur_params), and these windows are on mango's no_blur list
// (~/.config/mango/shell.conf).
//
// dim 0 (that window's "darken" setting off): no backdrop, as before, when
// mango blurred nothing; the card brings its own frost (WallpaperFrost).
Item {
    id: root

    property bool shown: false
    property real dim: 0.25

    visible: opacity > 0.001
    opacity: shown && dim > 0 ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
    }

    // A small copy is plenty under this much blur, and cheap to blur. A
    // fixed size, not one that follows the window: the window is 0 wide on
    // its first frame, so the picture was decoded twice, the second time
    // halfway into the fade. The same size as WallpaperFrost's, so they
    // share one decoded copy. It also shows as it is underneath:
    // MultiEffect's blur comes out a few percent see-through, which let
    // bright text behind show faintly.
    Image {
        id: picture
        anchors.fill: parent
        source: SmallWallpaper.source
        sourceSize: SmallWallpaper.size
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    Image {
        anchors.fill: parent
        source: picture.source
        sourceSize: picture.sourceSize
        fillMode: Image.PreserveAspectCrop
    }

    MultiEffect {
        anchors.fill: parent
        source: picture
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: Style.backdropBlur
        blur: 1
        saturation: 0.2
        brightness: -0.08
        contrast: -0.08
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.dim
    }
}
