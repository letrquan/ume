import QtQuick
import qs.common

// The answer field under a chat notification (inline reply):
//   ( Reply to Minh…                        [➤] )
// Enter or ➤ sends, Esc closes it. It takes the keyboard as it opens.
Item {
    id: root

    property string hint: ""

    signal sent(string text)
    signal cancelled()

    function focusField() {
        input.forceActiveFocus();
    }

    implicitHeight: 38

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Style.alpha(Colors.textOnSurface, 0.08)
        border.width: 1
        border.color: input.activeFocus ? Colors.primary : Style.alpha(Colors.textOnSurface, 0.12)

        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    }

    // Clicks in the field stay in the field (not "open the notification").
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()
    }

    TextInput {
        id: input
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: send.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        color: Colors.textOnSurface
        selectionColor: Style.alpha(Colors.primary, 0.4)
        font.family: Style.font
        font.pixelSize: Style.textSize("body")
        clip: true
        onAccepted: send.clicked(null)
        Keys.onEscapePressed: root.cancelled()

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            text: root.hint || "Reply…"
            color: Colors.textOnSurfaceVariant
            elide: Text.ElideRight
            visible: input.text === ""
        }
    }

    // Send: lights up once there's something to send.
    MouseArea {
        id: send
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 30
        enabled: input.text.trim() !== ""
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (input.text.trim() === "")
                return;
            root.sent(input.text);
            input.text = "";
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: send.enabled ? Colors.primary : "transparent"
            scale: send.pressed ? 0.9 : 1
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on scale {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
            }
        }
        Icon {
            anchors.centerIn: parent
            name: "send"
            size: 16
            fill: send.enabled ? 1 : 0
            color: send.enabled ? Colors.textOnPrimary : Colors.textOnSurfaceVariant
        }
    }
}
