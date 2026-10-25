import QtQuick
import QtQuick.Effects

// The frost under a glass card whose window mango doesn't blur (the
// notification center; the power menu, the cheat sheet and the password
// dialog with their darkening off): the piece of the blurred wallpaper
// right under the card, cut to its rounded shape. That's what mango's blur
// showed there (blur_optimized: the wallpaper, not your windows), but this
// one fades and scales with the card instead of popping in at full
// strength on its first frame and staying until its last.
//
// Put it first inside the card, filling it, with `at` = the card's place on
// the screen (its x and y in a window that covers the screen; for a smaller
// window, add the window's place and set screenWidth/screenHeight). It
// doesn't follow the card's scale-in: a blurred picture a few pixels off
// doesn't show.
Item {
    id: root

    property point at: Qt.point(0, 0)
    property real radius: Style.islandRadius
    // The screen's size: the window's, unless it doesn't cover the screen
    // (the OSD's), then its owner says.
    property real screenWidth: Window.window?.width ?? width
    property real screenHeight: Window.window?.height ?? height

    layer.enabled: true
    layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: shape
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    // The whole screen's blurred wallpaper (small: it's blurred a lot),
    // shifted so the card's piece is the part that shows.
    Image {
        id: picture
        x: -root.at.x
        y: -root.at.y
        width: root.screenWidth
        height: root.screenHeight
        // Fixed, and Backdrop's: one decoded copy, kept (SmallWallpaper.qml).
        source: SmallWallpaper.source
        sourceSize: SmallWallpaper.size
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    // Underneath as it is: MultiEffect's blur comes out a few percent
    // see-through.
    Image {
        x: picture.x
        y: picture.y
        width: picture.width
        height: picture.height
        source: picture.source
        sourceSize: picture.sourceSize
        fillMode: Image.PreserveAspectCrop
    }
    MultiEffect {
        x: picture.x
        y: picture.y
        width: picture.width
        height: picture.height
        source: picture
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: Style.backdropBlur
        blur: 1
        saturation: 0.2
        brightness: -0.08
        contrast: -0.08
    }

    Item {
        id: shape
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: root.radius
        }
    }
}
