import QtQuick
import qs.common

// The password capsule, same as on the lock screen: each typed character
// pops in as a random Material shape and morphs into a dot; the round
// button morphs while checking; the whole thing shakes and turns red on a
// wrong password. With `visibleText` (polkit asks for something that isn't
// secret) it shows the real text instead.
Item {
    id: root

    property string state_: "idle"      // idle | busy | failed
    property string placeholder: "Password"
    property bool visibleText: false
    property alias text: input.text
    property alias input: input

    signal accepted()

    readonly property bool failed: state_ === "failed"
    readonly property var shapeQueue: {
        const shapes = ["Slanted", "Arch", "Fan", "Arrow", "SemiCircle", "Triangle", "Diamond", "ClamShell",
                        "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Ghostish", "SoftBurst"];
        for (let i = shapes.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [shapes[i], shapes[j]] = [shapes[j], shapes[i]];
        }
        return shapes;
    }
    readonly property int charCell: 13

    implicitWidth: 360
    implicitHeight: 56

    function shake() {
        shakeAnim.restart();
    }
    onState_Changed: if (failed) shake()

    property real shakeX: 0
    transform: Translate { x: root.shakeX }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to: -16; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 13; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -9; duration: 75; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 5; duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 90; easing.type: Easing.OutQuad }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Style.alpha(Colors.surfaceContainerHigh, 0.8)
        border.width: input.activeFocus || root.failed ? 2 : 1
        border.color: root.failed ? Colors.error
                    : input.activeFocus ? Style.alpha(Colors.primary, 0.75)
                    : Style.alpha(Colors.outlineVariant, 0.8)
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }

    Item {
        id: dotsArea
        anchors.left: parent.left
        anchors.leftMargin: 22
        anchors.right: submit.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        height: root.charCell * 2
        clip: true
        visible: !root.visibleText

        // One row per character, only added/removed at the end, so existing
        // dots keep their state and only new ones animate.
        ListModel { id: charModel }
        Connections {
            target: input
            function onTextChanged() {
                const n = input.text.length;
                while (charModel.count < n)
                    charModel.append({ slot: charModel.count });
                if (charModel.count > n)
                    charModel.remove(n, charModel.count - n);
            }
        }

        ListView {
            anchors.verticalCenter: parent.verticalCenter
            x: contentWidth <= dotsArea.width ? (dotsArea.width - contentWidth) / 2 : dotsArea.width - contentWidth
            Behavior on x {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }
            width: Math.max(contentWidth, 1)
            height: root.charCell * 1.5
            orientation: ListView.Horizontal
            interactive: false
            spacing: 5
            model: charModel

            delegate: Item {
                id: charItem
                required property int slot
                width: root.charCell
                height: root.charCell * 1.5
                opacity: 0
                scale: 0

                ListView.onRemove: {
                    initAnim.stop();
                    removeAnim.start();
                }

                SequentialAnimation {
                    id: initAnim
                    running: true
                    ParallelAnimation {
                        NumberAnimation { target: charItem; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
                        NumberAnimation { target: charItem; property: "scale"; from: 0; to: 1; duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                        NumberAnimation { target: charItem; property: "width"; from: root.charCell; to: root.charCell * 1.3; duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
                    }
                    PauseAnimation { duration: 180 }
                    PropertyAction { target: charShape; property: "shape"; value: "Circle" }
                    ParallelAnimation {
                        NumberAnimation { target: charShape; property: "scale"; to: 2 / 3; duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                        NumberAnimation { target: charItem; property: "width"; to: root.charCell; duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
                    }
                }

                SequentialAnimation {
                    id: removeAnim
                    PropertyAction { target: charItem; property: "ListView.delayRemove"; value: true }
                    ParallelAnimation {
                        NumberAnimation { target: charItem; property: "opacity"; to: 0; duration: 200 }
                        NumberAnimation { target: charItem; property: "scale"; to: 0.5; duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                    }
                    PropertyAction { target: charItem; property: "ListView.delayRemove"; value: false }
                }

                Shape {
                    id: charShape
                    anchors.centerIn: parent
                    width: root.charCell * 1.5
                    height: root.charCell * 1.5
                    shape: root.shapeQueue[charItem.slot % root.shapeQueue.length]
                    color: root.failed ? Colors.error : Colors.textOnSurface
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }

        StyledText {
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width)
            opacity: input.text.length === 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            text: root.failed ? "Wrong password, try again" : root.state_ === "busy" ? "Checking…" : root.placeholder
            font.pixelSize: Style.textSize("title")
            color: root.failed ? Colors.error : root.state_ === "busy" ? Colors.secondary : Colors.outline
            elide: Text.ElideRight
        }
    }

    // The real input. Invisible for passwords (the shapes show it), shown
    // as plain text when polkit asks for something that isn't secret.
    TextInput {
        id: input
        anchors.fill: dotsArea
        verticalAlignment: TextInput.AlignVCenter
        opacity: root.visibleText ? 1 : 0
        focus: true
        color: Colors.textOnSurface
        font.family: Style.font
        font.pixelSize: Style.textSize("title")
        echoMode: root.visibleText ? TextInput.Normal : TextInput.Password
        passwordCharacter: "•"
        inputMethodHints: root.visibleText ? Qt.ImhNone : (Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText)
        enabled: root.state_ !== "busy"
        onAccepted: root.accepted()
    }

    // Submit: a circle with an arrow; morphs through shapes while checking.
    Item {
        id: submit
        width: 42
        height: 42
        anchors.right: parent.right
        anchors.rightMargin: 7
        anchors.verticalCenter: parent.verticalCenter

        property int busyStep: 0
        readonly property var busyShapes: ["Cookie9Sided", "Sunny", "Clover4Leaf", "Cookie6Sided", "Pentagon", "SoftBurst"]

        Timer {
            running: root.state_ === "busy"
            interval: 420
            repeat: true
            triggeredOnStart: true
            onTriggered: submit.busyStep++
        }

        Shape {
            anchors.fill: parent
            shape: root.state_ === "busy" ? submit.busyShapes[submit.busyStep % submit.busyShapes.length]
                 : root.failed ? "Pentagon"
                 : input.text.length > 0 ? "Cookie4Sided" : "Circle"
            color: root.failed ? Colors.error
                 : input.text.length > 0 || root.state_ !== "idle" ? Colors.primary
                 : Style.alpha(Colors.primary, 0.35)
            rotation: root.state_ === "busy" ? submit.busyStep * 60 : 0
            Behavior on color { ColorAnimation { duration: 250 } }
            Behavior on rotation { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        }

        Icon {
            anchors.centerIn: parent
            name: root.failed ? "close" : root.state_ === "busy" ? "" : "arrow_forward"
            size: 22
            color: root.failed ? Colors.textOnError : Colors.textOnPrimary
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.accepted()
        }
    }
}
