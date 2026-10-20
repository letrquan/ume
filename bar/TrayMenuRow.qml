import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.common

// One row of a tray menu: [check / radio / icon]  Text  [›]. Or a separator.
MouseArea {
    id: root

    property bool separator: false
    property string label: ""
    property string glyph: ""           // a Material Symbols name instead of an icon
    property string iconSource: ""
    property int buttonType: QsMenuButtonType.None
    property int checkState: Qt.Unchecked
    property bool hasChildren: false

    signal activated()

    implicitWidth: line.implicitWidth + 20
    implicitHeight: separator ? 9 : 34
    hoverEnabled: !separator
    cursorShape: separator ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: if (!separator) activated()

    Rectangle {
        anchors.centerIn: parent
        visible: root.separator
        width: parent.width - 16
        height: 1
        color: Style.alpha(Colors.textOnSurface, 0.12)
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.separator
        radius: 12
        color: Colors.textOnSurface
        opacity: !root.enabled ? 0 : root.pressed ? Style.pressTint : root.containsMouse ? Style.hoverTint : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    }

    Row {
        id: line
        visible: !root.separator
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        opacity: root.enabled ? 1 : 0.4

        // Check box / radio state, the app's icon, or our glyph.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            visible: root.buttonType !== QsMenuButtonType.None || root.iconSource !== "" || root.glyph !== ""

            Icon {
                anchors.centerIn: parent
                visible: root.buttonType !== QsMenuButtonType.None
                name: root.buttonType === QsMenuButtonType.RadioButton
                    ? (root.checkState === Qt.Checked ? "radio_button_checked" : "radio_button_unchecked")
                    : (root.checkState === Qt.Checked ? "check_box" : root.checkState === Qt.PartiallyChecked ? "indeterminate_check_box" : "check_box_outline_blank")
                size: 18
                color: root.checkState === Qt.Checked ? Colors.primary : Colors.textOnSurfaceVariant
            }
            IconImage {
                anchors.fill: parent
                visible: root.buttonType === QsMenuButtonType.None && root.iconSource !== ""
                source: root.iconSource
                asynchronous: true
            }
            Icon {
                anchors.centerIn: parent
                visible: root.glyph !== ""
                name: root.glyph
                size: 18
                color: Colors.textOnSurfaceVariant
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 290)
            // Menus mark keyboard shortcuts with _ ("_File"); "__" is a real _.
            text: root.label.replace(/__/g, "\u0000").replace(/_/g, "").replace(/\u0000/g, "_")
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
    }

    Icon {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasChildren && !root.separator
        name: "chevron_right"
        size: 18
        color: Colors.textOnSurfaceVariant
    }
}
