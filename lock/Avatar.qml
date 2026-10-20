import QtQuick
import QtQuick.Effects
import qs.common

// Your picture (~/.face) cut into a 12-sided cookie inside a slowly turning
// ring (the mask turns, the picture doesn't). The ring turns red and the
// picture bumps when the password is wrong.
Item {
    id: root

    property string source: ""
    property string userName: ""
    property bool failed: false

    property real spin: 0
    NumberAnimation on spin { from: 0; to: 360; duration: 40000; loops: Animation.Infinite }

    onFailedChanged: if (failed) bump.restart()
    SequentialAnimation {
        id: bump
        NumberAnimation { target: root; property: "scale"; to: 0.9; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "scale"; to: 1.0; duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
    }

    // Ring
    Shape {
        anchors.fill: parent
        shape: "Cookie12Sided"
        rotation: root.spin
        color: root.failed ? Colors.error : Colors.primary
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Image {
        id: photo
        anchors.fill: parent
        anchors.margins: 5
        source: root.source !== "" ? "file://" + root.source : ""
        sourceSize: Qt.size(256, 256)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
    }
    Item {
        id: mask
        anchors.fill: photo
        visible: false
        layer.enabled: true

        Shape {
            anchors.fill: parent
            shape: "Cookie12Sided"
            rotation: root.spin
            color: "white"
        }
    }
    MultiEffect {
        anchors.fill: photo
        visible: photo.status === Image.Ready
        source: photo
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    // No picture: the first letter of the user name.
    Shape {
        anchors.fill: photo
        visible: photo.status !== Image.Ready
        shape: "Cookie12Sided"
        rotation: root.spin
        color: Colors.primaryContainer
    }
    StyledText {
        anchors.centerIn: parent
        visible: photo.status !== Image.Ready
        text: root.userName.charAt(0).toUpperCase()
        color: Colors.textOnPrimaryContainer
        font.pixelSize: root.height * 0.4
        weight: 700
    }
}
