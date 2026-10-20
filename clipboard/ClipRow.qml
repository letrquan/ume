import QtQuick
import Quickshell.Widgets
import qs.common
import qs.services

// One clipboard entry: text (up to two lines) or a picture thumbnail with
// its size. A ✕ on hover (or the Delete key) forgets it.
Item {
    id: root

    required property var modelData
    required property int index
    property bool selected: false

    signal hoveredRow(int index)
    signal chosen(int index, bool paste)
    signal removed(int index)

    readonly property bool isImage: modelData.image

    width: ListView.view?.width ?? 0
    height: isImage ? Style.clipRowHeight + 30 : Style.clipRowHeight

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onPositionChanged: root.hoveredRow(root.index)
        // Click: paste; middle click: only copy.
        onClicked: mouse => root.chosen(root.index, mouse.button === Qt.LeftButton)
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: forget.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        // Text: a quiet glyph; picture: the thumbnail.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: root.isImage ? 112 : 30
            height: root.isImage ? 66 : 30

            Shape {
                anchors.fill: parent
                visible: !root.isImage
                shape: "Cookie4Sided"
                color: root.selected ? Colors.primary : Style.alpha(Colors.textOnSurface, 0.1)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
            Icon {
                anchors.centerIn: parent
                visible: !root.isImage
                name: /^https?:\/\//.test(root.modelData.text) ? "link" : "notes"
                size: 16
                color: root.selected ? Colors.textOnPrimary : Colors.textOnSurfaceVariant
            }

            ClippingRectangle {
                anchors.fill: parent
                visible: root.isImage
                radius: 10
                color: Style.alpha(Colors.textOnSurface, 0.08)

                Image {
                    anchors.fill: parent
                    // ?v=: a new address once the thumbnails are made, so it loads again.
                    source: root.isImage ? "file://" + Clipboard.thumbFor(root.modelData) + "?v=" + Clipboard.thumbsVersion : ""
                    sourceSize: Qt.size(224, 132)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (root.isImage ? 112 : 30) - parent.spacing
            text: root.isImage ? "Picture  ·  " + root.modelData.imageInfo.replace(" ", "  ·  ") : root.modelData.text
            textFormat: Text.PlainText
            wrapMode: root.isImage ? Text.NoWrap : Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            role: "body"
            color: root.isImage ? Colors.textOnSurfaceVariant : (root.selected ? Colors.textOnSurface : Style.alpha(Colors.textOnSurface, 0.85))
        }
    }

    // Forget this one.
    Clickable {
        id: forget
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: 28
        padding: 0
        opacity: mouse.containsMouse || hovered ? 1 : 0
        readonly property bool hovered: containsMouse
        onClicked: root.removed(root.index)

        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        Icon {
            name: "close"
            size: 16
            color: Colors.textOnSurfaceVariant
        }
    }
}
