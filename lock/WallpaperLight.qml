import QtQuick
import qs.common

// How bright the wallpaper is where the lock's words and pills sit, so they
// stay readable on a bright one. Read once per wallpaper from a tiny copy:
// the picture is drawn into this 64 px wide canvas the way the lock shows it
// (centered, cropped to the screen), then each region's brightness is
// taken from its pixels. Nothing is read again until the wallpaper changes.
//
// Each value goes from 0 (dark enough: everything looks as it always did)
// to 1 (bright: the strongest help), already through
// Style.lockFieldContrast ("light": always 0, "dark": always 1).
Canvas {
    id: root

    property string path: ""
    property real aspect: 0             // the picture's width / height (0 = not known yet)
    property real screenAspect: 16 / 10

    property real clock: 0              // the date and the time
    property real middle: 0             // the music card and "while you were away"
    property real user: 0               // your picture, your name and the line under the field
    property real field: 0              // the password field itself
    property real status: 0             // keyboard, Wi-Fi, battery (top right)
    property real power: 0              // ⏻ (bottom right)
    property real chip: 0               // the login screen's session chip (bottom left)

    // Where each sits, as parts of the screen: [left, top, right, bottom].
    readonly property var regions: ({
        clock: [0.25, 0.04, 0.75, 0.30],
        middle: [0.30, 0.28, 0.70, 0.45],
        user: [0.36, 0.66, 0.64, 0.92],
        field: [0.40, 0.78, 0.60, 0.88],
        status: [0.80, 0.00, 1.00, 0.07],
        power: [0.88, 0.86, 1.00, 1.00],
        chip: [0.00, 0.88, 0.20, 1.00]
    })
    // Measured brightness of each region (0..1, -1 = not measured).
    property var raw: ({})

    Behavior on clock { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on middle { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on user { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on field { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on status { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on power { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on chip { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }

    readonly property string url: path !== "" ? "file://" + path : ""
    property string loaded: ""

    width: 64
    height: Math.max(1, Math.round(64 / screenAspect))
    opacity: 0                          // painted, never seen

    // smoothstep(lo, hi, b): below lo nothing changes, above hi the most.
    function amount(b) {
        if (Style.lockFieldContrast === "light" || b === undefined || b < 0)
            return Style.lockFieldContrast === "dark" ? 1 : 0;
        if (Style.lockFieldContrast === "dark")
            return 1;
        const t = Math.max(0, Math.min(1, (b - Style.lockContrastFrom) / Math.max(0.01, Style.lockContrastTo - Style.lockContrastFrom)));
        return t * t * (3 - 2 * t);
    }
    function apply() {
        for (const name in regions)
            root[name] = amount(raw[name] ?? -1);
    }
    onRawChanged: apply()
    Connections {
        target: Style
        function onLockFieldContrastChanged() { root.apply(); }
        function onLockContrastFromChanged() { root.apply(); }
        function onLockContrastToChanged() { root.apply(); }
    }
    Component.onCompleted: apply()

    function measure() {
        if (url === "" || aspect <= 0 || url === loaded)
            return;
        if (loaded !== "")
            unloadImage(loaded);
        loaded = url;
        raw = ({});
        // The size it's decoded at: as small as the canvas needs.
        loadImage(url, Qt.size(Math.ceil(Math.max(width, height * aspect)), Math.ceil(Math.max(height, width / aspect))));
    }
    onUrlChanged: measure()
    onAspectChanged: measure()
    onScreenAspectChanged: {
        loaded = "";
        measure();
    }
    onImageLoaded: requestPaint()

    onPaint: {
        if (loaded === "" || !isImageLoaded(loaded))
            return;
        const ctx = getContext("2d");
        // Cover the canvas like Image.PreserveAspectCrop.
        const dw = Math.max(width, height * aspect);
        const dh = dw / aspect;
        ctx.clearRect(0, 0, width, height);
        ctx.drawImage(loaded, (width - dw) / 2, (height - dh) / 2, dw, dh);
        const px = ctx.getImageData(0, 0, width, height).data;
        const out = {};
        for (const name in regions) {
            const r = regions[name];
            const x0 = Math.floor(r[0] * width), x1 = Math.max(x0 + 1, Math.ceil(r[2] * width));
            const y0 = Math.floor(r[1] * height), y1 = Math.max(y0 + 1, Math.ceil(r[3] * height));
            const lum = [];
            for (let y = y0; y < y1; y++)
                for (let x = x0; x < x1; x++) {
                    const i = (y * width + x) * 4;
                    lum.push((0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2]) / 255);
                }
            // The brighter part counts most (text over a bright patch is
            // what's hard to read): the value three quarters of the way up.
            lum.sort((a, b) => a - b);
            out[name] = lum[Math.min(lum.length - 1, Math.floor(lum.length * 0.75))];
        }
        unloadImage(loaded);
        raw = out;
        console.log("lock: wallpaper brightness", JSON.stringify(out, (k, v) => typeof v === "number" ? Math.round(v * 100) / 100 : v));
    }
}
