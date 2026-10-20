import QtQuick
import Quickshell

// An app's icon, the same way everywhere (launcher, dock, workspaces, the
// window title, Alt+Tab, notifications, the System popup, sound, overview,
// lock): on one shared tile, a squircle like macOS app icons, in glass
// tinted from the wallpaper (Style.appIconStyle "tile"), or bare ("plain").
//
// An icon that can't be found doesn't show Qt's magenta-and-black
// "missing" square: the app's first letter goes on a tile colored from its
// name instead (always, also with "plain"). Qt's icon loader still says
// "Ready" for a missing theme icon (status is never Error), so a theme name
// is checked with Quickshell.hasThemeIcon() first; a file that won't load
// does give Error.
//
//   source: "firefox", "image://icon/firefox",
//           "image://icon/firefox?fallback=application-x-executable"
//           (Quickshell.iconPath; the fallback is ignored, the letter is
//           the fallback), "image://icon//abs/path.svg", "file:///abs",
//           "/abs/path", or a notification's "image://qsimage/…".
//   name:   the app's name, for the letter and its color ("" = taken from
//           the icon's name).
Item {
    id: root

    property string source: ""
    property string name: ""
    property real implicitSize: 32
    property bool tiled: Style.appIconStyle !== "plain"
    // How much of the tile the icon fills.
    property real inner: Style.appIconInner
    // Size the picture is decoded at; empty = the drawn size. The dock
    // decodes once at its biggest so growing on hover never reloads it.
    property size sourceSize: Qt.size(0, 0)
    property bool asynchronous: true
    property bool mipmap: false
    // The tile's color, when a place wants its own (critical notifications).
    property color tileColor: "transparent"
    // For the letter when there's no icon: false draws only the letter
    // (for places that already sit the icon on a shape of their own).
    property bool letterTile: true
    property color letterColor: root.letterColors[1]

    readonly property alias status: img.status
    // Nothing to show but the letter: no icon, a theme name the theme
    // doesn't have, or a file that didn't load.
    readonly property bool unknown: parsed.url === ""
        || (parsed.theme !== "" && !Quickshell.hasThemeIcon(parsed.theme))
    readonly property bool missing: unknown || img.status === Image.Error

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    // { url, theme }: what to load, and the theme name to check first.
    readonly property var parsed: {
        let s = root.source ?? "";
        if (s.startsWith("image://icon/")) {
            s = s.slice(13);
            const q = s.indexOf("?");
            if (q >= 0)
                s = s.slice(0, q);
            if (s.startsWith("/"))
                return { url: "file://" + s, theme: "" };
            return { url: s === "" ? "" : "image://icon/" + s, theme: s };
        }
        if (s.startsWith("/"))
            return { url: "file://" + s, theme: "" };
        // Pictures on this computer only (file:, image:, qrc:); never fetched.
        if (s.includes("://"))
            return { url: /^(file|image|qrc):/.test(s) ? s : "", theme: "" };
        return { url: s === "" ? "" : "image://icon/" + s, theme: s };
    }

    // The name the letter and color come from: the app's, else the icon's
    // ("org.gnome.Nautilus" → "Nautilus", "/a/b/telegram.svg" → "telegram").
    readonly property string key: {
        if (root.name !== "")
            return root.name;
        const s = (root.parsed.theme || root.parsed.url).split("/").pop().split("?")[0];
        return s.replace(/\.(png|svg|svgz|xpm|jpg|jpeg)$/i, "").split(".").pop();
    }
    // The first letter or digit (whole code point, so emoji and "Đ" work).
    readonly property string letter: {
        for (const ch of root.key) {
            if (" \t-_.,:;!?@#$%^&*+=~`'\"()[]{}<>/\\|".includes(ch))
                continue;
            return ch.toUpperCase();
        }
        return "";
    }
    // One of the three accent containers, always the same for a name.
    readonly property var letterColors: {
        let h = 0;
        const k = root.key.toLowerCase();
        for (let i = 0; i < k.length; i++)
            h = (h * 31 + k.charCodeAt(i)) | 0;
        switch (Math.abs(h) % 3) {
        case 0: return [Colors.primaryContainer, Colors.textOnPrimaryContainer];
        case 1: return [Colors.secondaryContainer, Colors.textOnSecondaryContainer];
        default: return [Colors.tertiaryContainer, Colors.textOnTertiaryContainer];
        }
    }

    // No icon and no name: nothing at all (a place that hasn't looked yet).
    readonly property bool empty: root.source === "" && root.name === ""
    readonly property bool showTile: !root.empty && (root.missing ? root.letterTile : root.tiled)
    readonly property color fill: root.missing ? root.letterColors[0]
        : root.tileColor.a > 0 ? root.tileColor
        : Style.alpha(Colors.surfaceContainerHighest, Style.appIconTileOpacity)

    ShaderEffect {
        anchors.fill: parent
        visible: root.showTile

        // c moved toward white (k > 0) or black (k < 0), premultiplied.
        function shade(c, k) {
            const t = k > 0 ? 1 : 0, a = Math.abs(k);
            const r = c.r + (t - c.r) * a, g = c.g + (t - c.g) * a, b = c.b + (t - c.b) * a;
            return Qt.vector4d(r * c.a, g * c.a, b * c.a, c.a);
        }
        // Lighter at the top, a little darker at the bottom: light from above.
        readonly property vector2d itemSize: Qt.vector2d(width, height)
        readonly property vector4d topPm: shade(root.fill, 0.07)
        readonly property vector4d bottomPm: shade(root.fill, -0.06)
        readonly property vector4d rimPm: shade(Qt.rgba(1, 1, 1, Style.appIconRim), 0)
        readonly property real rimWidth: 1
        readonly property real power: 4.6

        fragmentShader: Qt.resolvedUrl("shaders/squircle.frag.qsb")
    }

    Image {
        id: img
        anchors.centerIn: parent
        // Small tiles (the bar's 16 px) give the icon a little more room,
        // or it would shrink to a dot. Whole pixels where the size is fixed,
        // exact where it's animated (the dock grows its icons every frame).
        readonly property real full: Math.min(root.width, root.height)
        readonly property real fit: Math.min(0.94, root.inner + Math.max(0, 24 - full) * 0.015)
        readonly property real exact: root.tiled ? full * fit : full
        readonly property real side: root.sourceSize.width > 0 ? exact : Math.round(exact)
        width: side
        height: side
        visible: !root.missing
        source: root.unknown ? "" : root.parsed.url
        sourceSize: root.sourceSize.width > 0 ? root.sourceSize : Qt.size(side, side)
        fillMode: Image.PreserveAspectFit
        asynchronous: root.asynchronous
        mipmap: root.mipmap
        smooth: true
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.missing
        text: root.letter
        font.pixelSize: Math.max(8, Math.round(Math.min(root.width, root.height) * (root.letterTile ? 0.5 : 0.6)))
        weight: 700
        color: root.letterTile ? root.letterColors[1] : root.letterColor
    }
}
