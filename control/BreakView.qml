import QtQuick
import qs.common
import qs.services

// The break countdown's card (control/BreakWindow.qml): a ring running out
// with the time left in it, a line of advice and Skip; once it's over and
// you're still away, "Welcome back" waits for you.
Item {
    id: root

    property bool open: false
    readonly property bool after: Breaks.phase === "after"
    readonly property real total: Breaks.lengthMs
    readonly property string leftText: {
        const s = Math.ceil(Breaks.breakLeft / 1000);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    implicitWidth: 340
    implicitHeight: column.implicitHeight + 56
    width: implicitWidth
    height: implicitHeight

    opacity: open ? 1 : 0
    scale: open ? 1 : 0.94
    Behavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects } }
    Behavior on scale { NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

    Glass {
        anchors.fill: parent
        radius: Style.radiusDialog
        color: Style.alpha(Colors.surfaceContainer, Style.ccOpacity)
    }

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        y: 28
        width: parent.width - 56
        spacing: 14

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 148
            height: 148

            UsageRing {
                anchors.fill: parent
                size: 148
                thickness: 10
                gap: 0
                value: root.after ? 1 : root.total > 0 ? Breaks.breakLeft / root.total : 0
                color: root.after ? Colors.tertiary : Colors.primary
            }
            Column {
                anchors.centerIn: parent
                spacing: 2

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: root.after ? "waving_hand" : "self_improvement"
                    size: 26
                    color: Colors.textOnSurfaceVariant
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.after ? "Done" : root.leftText
                    role: "headline"
                    weight: 650
                    font.features: ({ "tnum": 1 })
                }
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.after ? "Welcome back" : "Take a breath"
            role: "title"
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.after ? "Break done. The clock starts over."
                : "Look far away, stretch, have some water. It's over when you come back after the countdown."
            color: Colors.textOnSurfaceVariant
        }

        MouseArea {
            id: skip
            anchors.horizontalCenter: parent.horizontalCenter
            width: 140
            height: 36
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Breaks.skipBreak()

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Style.alpha(Colors.textOnSurface, skip.pressed ? 0.2 : skip.containsMouse ? 0.14 : 0.09)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
            StyledText {
                anchors.centerIn: parent
                text: root.after ? "Back to work" : "Skip"
            }
        }
    }
}
