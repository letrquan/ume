import QtQuick
import qs.common
import qs.services

// One app playing sound: its icon (click: mute), its name, and a slim
// slider (drag, click anywhere, or scroll).
Item {
    id: root

    required property var node
    readonly property real value: node?.audio?.volume ?? 0
    readonly property bool muted: node?.audio?.muted ?? false

    // While dragging, show where the finger is, not the system's echo.
    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: Math.max(0, Math.min(1, dragging ? dragValue : value))

    implicitHeight: 44

    // App icon: click to mute.
    MouseArea {
        id: iconArea
        width: 36
        height: 36
        anchors.verticalCenter: parent.verticalCenter
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ControlState.toggleMute(root.node)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colors.textOnSurface
            opacity: iconArea.pressed ? Style.pressTint : iconArea.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        AppIcon {
            anchors.centerIn: parent
            implicitSize: 24
            source: AppAudio.appsLoaded >= 0 ? AppAudio.icon(root.node) : ""
            name: AppAudio.name(root.node)
            opacity: root.muted ? 0.35 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Icon {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: root.muted
            name: "volume_off"
            size: 14
            color: Colors.error
        }
    }

    Item {
        id: body
        anchors.left: iconArea.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 4
        height: parent.height

        StyledText {
            id: label
            anchors.left: parent.left
            anchors.right: percent.left
            anchors.rightMargin: 8
            y: 4
            text: {
                const d = AppAudio.detail(root.node);
                return AppAudio.name(root.node) + (d !== "" ? "  ·  " + d : "");
            }
            role: "label"
            color: root.muted ? Colors.textOnSurfaceVariant : Colors.textOnSurface
            elide: Text.ElideRight
        }
        StyledText {
            id: percent
            anchors.right: parent.right
            y: 4
            text: root.muted ? "Off" : Math.round(root.shown * 100) + "%"
            role: "caption"
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }

        // Slim track and fill.
        Item {
            id: slider
            anchors.left: parent.left
            anchors.right: parent.right
            y: 24
            height: 14

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: Style.alpha(Colors.textOnSurface, 0.1)

                Rectangle {
                    height: parent.height
                    width: Math.max(parent.height, parent.width * root.shown)
                    radius: 3
                    color: root.muted ? Style.alpha(Colors.textOnSurface, 0.28) : Colors.primary

                    Behavior on width {
                        enabled: !root.dragging
                        NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                    }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }

            // The knob at the end of the fill.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(parent.width - width, parent.width * root.shown - width / 2))
                width: 14
                height: 14
                radius: 7
                color: root.muted ? Colors.textOnSurfaceVariant : Colors.primary
                scale: drag.pressed ? 1.2 : drag.containsMouse ? 1.1 : 1
                Behavior on scale { NumberAnimation { duration: Motion.fast } }
                Behavior on x {
                    enabled: !root.dragging
                    NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                }
            }

            MouseArea {
                id: drag
                anchors.fill: parent
                anchors.topMargin: -6
                anchors.bottomMargin: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function valueAt(x) {
                    return Math.max(0, Math.min(1, x / width));
                }
                onPressed: mouse => {
                    root.dragging = true;
                    root.dragValue = valueAt(mouse.x);
                    ControlState.setVolume(root.node, root.dragValue);
                }
                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    root.dragValue = valueAt(mouse.x);
                    ControlState.setVolume(root.node, root.dragValue);
                }
                onReleased: root.dragging = false
                onCanceled: root.dragging = false
                onWheel: wheel => {
                    const step = (wheel.angleDelta.y || -wheel.angleDelta.x) / 120 * 0.05;
                    ControlState.setVolume(root.node, Math.max(0, Math.min(1, root.value + step)));
                }
            }
        }
    }
}
