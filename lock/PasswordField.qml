import QtQuick
import qs.common

// The password capsule: typed characters animate like Caelestia's lock (a
// random Material shape that morphs into a dot), and a round button that
// morphs while checking. Shakes and turns red on a wrong password.
Item {
    id: root

    property string userName: "user"
    property string authState: "idle"      // idle | busy | failed | success
    property string message: ""            // PAM message (e.g. too many tries)
    property alias text: input.text
    property alias input: input

    signal accepted()

    readonly property bool failed: authState === "failed"
    // Caelestia's 15 character shapes, shuffled once each time the lock starts.
    readonly property var shapeQueue: {
        const shapes = ["Slanted", "Arch", "Fan", "Arrow", "SemiCircle", "Triangle", "Diamond", "ClamShell",
                        "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Ghostish", "SoftBurst"];
        for (let i = shapes.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [shapes[i], shapes[j]] = [shapes[j], shapes[i]];
        }
        return shapes;
    }
    readonly property int charCell: 14

    implicitWidth: 420
    implicitHeight: 64

    function shake() { shakeAnim.restart() }
    onAuthStateChanged: if (authState === "failed") shake()

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

    // Capsule
    Rectangle {
        id: capsule
        anchors.fill: parent
        radius: height / 2
        color: Style.alpha(Colors.textOnSurface, 0.08)
        border.width: input.activeFocus || root.failed ? 2 : 1
        border.color: root.failed ? Colors.error
                    : input.activeFocus ? Style.alpha(Colors.primary, 0.75)
                    : Style.alpha(Colors.textOnSurface, 0.12)
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }

    // Typed characters, Caelestia style (modules/lock/center/InputField.qml):
    // each one pops in as a random Material shape while its slot widens, then
    // after 180 ms morphs into a circle and shrinks to 2/3. Deleted ones fade
    // and shrink away. The dots stay centred in the field.
    Item {
        id: dotsArea
        anchors.left: parent.left
        anchors.leftMargin: 24
        anchors.right: submit.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: root.charCell * 2
        clip: true

        // One model row per character, only appended/removed at the end, so
        // existing dots keep their state and only new ones animate.
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
            id: charList
            anchors.verticalCenter: parent.verticalCenter
            // Centred while it fits; once longer than the field, keep the end in view.
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
                        NumberAnimation {
                            target: charItem; property: "opacity"; from: 0; to: 1; duration: 200
                            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects
                        }
                        NumberAnimation {
                            target: charItem; property: "scale"; from: 0; to: 1; duration: Motion.fast
                            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial
                        }
                        NumberAnimation {
                            target: charItem; property: "width"; from: root.charCell; to: root.charCell * 1.3; duration: 200
                            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects
                        }
                    }
                    PauseAnimation { duration: 180 }
                    // Morph into a circle (the shape library animates the morph).
                    PropertyAction { target: charShape; property: "shape"; value: "Circle" }
                    ParallelAnimation {
                        NumberAnimation {
                            target: charShape; property: "scale"; to: 2 / 3; duration: Motion.fast
                            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial
                        }
                        NumberAnimation {
                            target: charItem; property: "width"; to: root.charCell; duration: 200
                            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects
                        }
                    }
                }

                SequentialAnimation {
                    id: removeAnim
                    PropertyAction { target: charItem; property: "ListView.delayRemove"; value: true }
                    ParallelAnimation {
                        NumberAnimation {
                            target: charItem; property: "opacity"; to: 0; duration: 200
                            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects
                        }
                        NumberAnimation {
                            target: charItem; property: "scale"; to: 0.5; duration: 300
                            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial
                        }
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
            opacity: input.text.length === 0 ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
            }
            text: root.message !== "" ? root.message
                : root.failed ? "Incorrect password"
                : root.authState === "busy" ? "Checking…"
                : "Enter your password"
            color: root.failed || root.message !== "" ? Colors.error
                 : root.authState === "busy" ? Colors.secondary
                 : Colors.textOnSurfaceVariant
            elide: Text.ElideRight
            width: Math.min(implicitWidth, parent.width)
            font.pixelSize: Style.textSize("headline")
        }
    }

    // The real input is invisible; the shapes above show what was typed.
    TextInput {
        id: input
        anchors.fill: dotsArea
        opacity: 0
        focus: true
        echoMode: TextInput.Password
        passwordCharacter: "•"
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText
        enabled: root.authState !== "busy" && root.authState !== "success"
        onAccepted: root.accepted()
        Keys.onEscapePressed: text = ""
    }

    // Submit: a circle with an arrow; morphs through shapes while checking.
    Item {
        id: submit
        width: 48; height: 48
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter

        property int busyStep: 0
        readonly property var busyShapes: ["Cookie9Sided", "Sunny", "Clover4Leaf", "Cookie6Sided", "Pentagon", "SoftBurst"]

        Timer {
            running: root.authState === "busy"
            interval: 420; repeat: true; triggeredOnStart: true
            onTriggered: submit.busyStep++
        }

        Shape {
            id: submitShape
            anchors.fill: parent
            shape: root.authState === "busy" ? submit.busyShapes[submit.busyStep % submit.busyShapes.length]
                 : root.authState === "success" ? "Cookie12Sided"
                 : root.failed ? "Pentagon"
                 : input.text.length > 0 ? "Cookie4Sided" : "Circle"
            color: root.failed ? Colors.error
                 : input.text.length > 0 || root.authState !== "idle" ? Colors.primary
                 : Style.alpha(Colors.primary, 0.35)
            Behavior on color { ColorAnimation { duration: 250 } }
            rotation: root.authState === "busy" ? submit.busyStep * 60 : 0
            Behavior on rotation { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        }

        Icon {
            anchors.centerIn: parent
            name: root.authState === "success" ? "check"
                : root.failed ? "close"
                : root.authState === "busy" ? "" : "arrow_forward"
            size: 24
            color: root.failed ? Colors.textOnError : Colors.textOnPrimary
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.accepted()
        }
    }
}
