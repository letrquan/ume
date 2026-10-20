import QtQuick
import Quickshell.Widgets

// Your picture (~/.face) in a plain circle, like a Mac's login picture.
// Without one: the first letter of your name on a frosted-white circle.
Item {
    id: root

    property string source: ""
    property string name: ""

    ClippingRectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.22)

        Text {
            anchors.centerIn: parent
            visible: photo.status !== Image.Ready
            text: root.name.charAt(0).toUpperCase()
            color: "white"
            font.pixelSize: root.height * 0.42
            font.weight: Font.DemiBold
        }
        Image {
            id: photo
            anchors.fill: parent
            source: root.source !== "" ? "file://" + root.source : ""
            sourceSize: Qt.size(root.width * 2, root.height * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }
    }
}
