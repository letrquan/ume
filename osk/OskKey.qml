import QtQuick
import qs.common
import qs.services

// One key. It types the moment it's touched (OskState.tap); ⌫ and the
// arrows repeat while held. A TapHandler each, so two fingers (or the pen)
// on two keys both count.
Item {
    id: root

    required property var key
    property real gap: 6

    objectName: "oskKey:" + key.id
    readonly property bool repeats: ["back", "left", "right", "up", "down"].includes(key.t)
    readonly property bool isChar: key.c !== undefined
    readonly property bool shifted: OskState.shift !== "off"
    // ⇧ / ctrl / alt / super waiting for the next key.
    readonly property bool latched: key.t === "shift" ? shifted
        : key.t === "ctrl" ? OskState.ctrl
        : key.t === "alt" ? OskState.alt
        : key.t === "super" ? OskState.superKey : false
    property bool down: false
    // What the touch typed: a held key sends it again.
    property var sent: null

    // The TapHandler calls these (tests call them too).
    function press() {
        if (down)
            return;
        down = true;
        sent = OskState.tap(key);
        if (repeats)
            delay.restart();
    }

    function release() {
        down = false;
        delay.stop();
        ticker.stop();
    }

    Timer {
        id: delay
        interval: Style.oskRepeatDelay
        onTriggered: ticker.start()
    }

    Timer {
        id: ticker
        interval: Style.oskRepeatInterval
        repeat: true
        onTriggered: OskState.again(root.sent)
    }

    // Grabs the touch on press; letting go or sliding off the key ends it.
    TapHandler {
        gesturePolicy: TapHandler.WithinBounds
        onPressedChanged: {
            if (pressed)
                root.press();
            else
                root.release();
        }
    }

    readonly property var icons: ({
        shift: OskState.shift === "caps" ? "shift_lock" : "shift",
        back: "backspace", enter: "keyboard_return", tab: "keyboard_tab",
        "super": "keyboard_command_key", hide: "keyboard_hide",
        left: "keyboard_arrow_left", right: "keyboard_arrow_right",
        up: "keyboard_arrow_up", down: "keyboard_arrow_down"
    })
    readonly property var words: ({
        ctrl: "ctrl", alt: "alt", esc: "esc",
        page: OskState.page === "letters" ? "?123" : "ABC"
    })
    // What ⇧ would give instead, in the corner (not for plain capitals).
    readonly property string other: isChar && key.s !== key.c.toUpperCase() ? (shifted ? key.c : key.s) : ""

    Rectangle {
        id: face

        anchors.fill: parent
        anchors.margins: root.gap / 2
        radius: Style.oskKeyRadius
        color: root.down ? Style.alpha(Colors.primary, 0.5)
            : root.latched ? Colors.primaryContainer
            : root.isChar ? Style.alpha(Colors.surfaceContainerHighest, 0.75)
            : Style.alpha(Colors.surfaceContainerLowest, 0.45)
        scale: root.down ? 0.94 : 1

        // Lights up at once, fades back.
        Behavior on color {
            enabled: !root.down
            ColorAnimation { duration: Motion.fast }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }

        StyledText {
            anchors.centerIn: parent
            visible: root.isChar || root.words[root.key.t] !== undefined
            text: root.isChar ? (root.shifted ? root.key.s : root.key.c) : (root.words[root.key.t] ?? "")
            font.pixelSize: Math.round(root.isChar ? face.height * 0.42 : face.height * 0.3)
            color: root.latched ? Colors.textOnPrimaryContainer : Colors.textOnSurface
        }

        StyledText {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Math.round(face.height * 0.1)
            visible: root.other !== ""
            text: root.other
            font.pixelSize: Math.round(face.height * 0.24)
            color: Colors.textOnSurfaceVariant
            opacity: 0.8
        }

        Icon {
            anchors.centerIn: parent
            visible: root.icons[root.key.t] !== undefined
            name: root.icons[root.key.t] ?? ""
            size: Math.round(face.height * 0.42)
            fill: root.latched ? 1 : 0
            color: root.latched ? Colors.textOnPrimaryContainer : Colors.textOnSurface
        }
    }
}
