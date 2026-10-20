import QtQuick
import qs.common

// The mac style's password field: a small frosted pill with "Enter
// Password", plain dots while you type, and a round → inside on the right
// once there's something to send (a spinner while it's checked). A wrong
// password shakes it side to side, like a Mac. Esc clears it.
Item {
    id: root

    required property Item source      // the lock's background, for the frost
    property rect area: Qt.rect(x, y, width, height)
    property string authState: "idle"  // idle | busy | failed | success
    // 0 → 1 as the picture behind gets bright: a darker field, a stronger
    // "Enter Password" (MacView's WallpaperLight).
    property real boost: 0
    property alias text: input.text
    property alias input: input

    signal accepted()
    signal typed()                     // any key, even ones that change nothing

    readonly property bool busy: authState === "busy"
    readonly property bool failed: authState === "failed"

    implicitWidth: 230
    implicitHeight: 34

    onAuthStateChanged: if (failed) shakeAnim.restart()

    // Damped, side to side, about half a second.
    property real shakeX: 0
    transform: Translate { x: root.shakeX }
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to: -14; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 12; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -9; duration: 75; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 6; duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -3; duration: 65; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 90; easing.type: Easing.OutQuad }
    }

    Frosted {
        anchors.fill: parent
        source: root.source
        area: root.area
        radius: height / 2
        tint: Qt.rgba(1 - root.boost, 1 - root.boost, 1 - root.boost, 0.2 * (1 - root.boost) + 0.42 * root.boost)
        saturation: -0.5
    }

    StyledText {
        anchors.centerIn: parent
        visible: input.text.length === 0
        text: "Enter Password"
        color: Qt.rgba(1, 1, 1, 0.62 + 0.3 * root.boost)
        font.pixelSize: Style.textSize("body")
    }

    TextInput {
        id: input
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: send.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        echoMode: TextInput.Password
        passwordCharacter: "●"
        passwordMaskDelay: 0
        readOnly: root.busy
        color: "white"
        selectionColor: Qt.rgba(1, 1, 1, 0.3)
        font.family: Style.font
        font.pixelSize: Style.textSize("micro")
        font.letterSpacing: 3
        // The caret only while there's text (the placeholder sits in the middle).
        cursorVisible: activeFocus && text.length > 0
        cursorDelegate: Rectangle {
            width: 1.5
            color: "white"
            visible: input.cursorVisible
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => {
            root.typed();
            if (event.key === Qt.Key_Escape) {
                input.text = "";
                event.accepted = true;
            }
        }
        onAccepted: root.accepted()
    }

    // → (or a spinner while checking), in a small round button.
    Item {
        id: send
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        readonly property bool shown: input.text.length > 0 || root.busy
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        Behavior on scale {
            NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(1, 1, 1, sendTap.pressed ? 0.42 : sendHover.hovered ? 0.34 : 0.24)
            visible: !root.busy
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
        Icon {
            anchors.centerIn: parent
            visible: !root.busy
            name: "arrow_forward"
            size: 16
            color: "white"
        }
        Icon {
            anchors.centerIn: parent
            visible: root.busy
            name: "progress_activity"
            size: 20
            color: "white"
            RotationAnimation on rotation {
                running: root.busy
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
            }
        }

        HoverHandler { id: sendHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: sendTap; onTapped: if (input.text.length > 0) root.accepted() }
    }
}
