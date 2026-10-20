import QtQuick
import Quickshell.Widgets
import qs.common

// One launcher result: an app or file icon (or a shape with a glyph for
// the calculator, web and hint rows), the name, and a quiet description
// (a file's folder).
Item {
    id: root

    required property var modelData
    required property int index
    property bool selected: false

    signal hoveredRow(int index)
    signal chosen(int index)

    readonly property bool isApp: modelData.kind === "app" || modelData.kind === "file"
    readonly property bool isHint: modelData.kind === "hint"

    width: ListView.view?.width ?? 0
    height: Style.launcherRowHeight

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.isHint ? Qt.ArrowCursor : Qt.PointingHandCursor
        // Only a real mouse move selects, so scrolling with the keys
        // doesn't fight a still cursor.
        onPositionChanged: root.hoveredRow(root.index)
        onClicked: root.chosen(root.index)
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        // An app icon on a tile gets a slightly bigger box, so the icon
        // itself stays about as big as a bare one.
        Item {
            id: iconBox
            anchors.verticalCenter: parent.verticalCenter
            width: Style.appIconStyle === "plain" ? 32 : 36
            height: width

            // Apps on their tile (a letter when the icon is missing); files
            // keep their type's icon (it has its own fallback).
            AppIcon {
                readonly property bool app: root.modelData.kind === "app"
                anchors.fill: parent
                visible: app
                source: app ? root.modelData.icon : ""
                name: app ? root.modelData.title : ""
            }
            IconImage {
                anchors.fill: parent
                visible: root.modelData.kind === "file"
                source: root.modelData.kind === "file" ? root.modelData.icon : ""
                asynchronous: true
            }

            Shape {
                anchors.fill: parent
                visible: !root.isApp
                shape: root.modelData.kind === "calc" ? "Cookie4Sided" : "Cookie9Sided"
                color: root.selected ? Colors.primary : Colors.secondaryContainer
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
            Icon {
                anchors.centerIn: parent
                visible: !root.isApp
                name: root.modelData.icon ?? ""
                size: 18
                color: root.selected ? Colors.textOnPrimary : Colors.textOnSecondaryContainer
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - iconBox.width - 12 - sub.width - 12)
            text: root.modelData.title
            role: root.modelData.kind === "calc" ? "headline" : "title"
            color: root.isHint ? Colors.textOnSurfaceVariant : root.selected ? Colors.primary : Colors.textOnSurface
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            elide: Text.ElideRight
        }

        StyledText {
            id: sub
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, (parent.width - iconBox.width - 12) * 0.55)
            text: root.modelData.subtitle
            role: "caption"
            color: Colors.textOnSurfaceVariant
            // A folder path keeps its start and its end.
            elide: root.modelData.kind === "file" ? Text.ElideMiddle : Text.ElideRight
            visible: text !== ""
        }
    }
}
