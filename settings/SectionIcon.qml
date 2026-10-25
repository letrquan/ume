import QtQuick
import qs.common
import "../services/termcolors.js" as Tc

// A section's icon on a small colored square, like System Settings. The
// wallpaper's palette is shades of one color, too few to tell 18 sections
// apart, so each section keeps a hue of its own (below) and the set is turned
// a little toward the wallpaper's color (as the terminal's colors are, in
// services/termcolors.js), all at the same lightness. Sections without a
// hue get a grey with a touch of the wallpaper in it.
Rectangle {
    id: root

    property string section: ""
    property string icon: ""
    property real size: 26
    property real fill: 1

    // OKLCH hue per section; -1 = grey.
    readonly property var hues: ({
        appearance: 300, bar: 255, baritems: 232, dock: 205, notifications: 25,
        activities: 55, sounds: 345, launcher: 265, panels: 180, keyboard: -1,
        wallpaper: 195, desktop: 240, screenshots: 285, recording: 12,
        power: 145, lock: -1, calendar: 30, about: -1, search: -1,
        controlcenter: 160
    })
    readonly property real hue: hues[section] ?? -1
    readonly property var source: Tc.toOklch(Colors.primary.toString())
    readonly property color base: {
        const grey = hue < 0;
        let h = grey ? source.h : hue;
        if (!grey) {
            // At most 10° toward the wallpaper's hue, none for a grey picture.
            const grip = Math.min(1, source.c / 0.05);
            const delta = ((source.h - hue + 540) % 360) - 180;
            h = hue + Math.sign(delta) * Math.min(Math.abs(delta) * 0.2, 10) * grip;
        }
        return Tc.toHex(grey ? 0.56 : 0.62, grey ? 0.018 : 0.14, h);
    }

    width: size
    height: size
    radius: Math.round(size * 0.28)
    // Lit from above, like the glass.
    gradient: Gradient {
        GradientStop { position: 0; color: Qt.lighter(root.base, 1.14) }
        GradientStop { position: 1; color: root.base }
    }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: Math.round(root.size * 0.64)
        fill: root.fill
        color: "#ffffff"
    }
}
