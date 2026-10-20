import QtQuick
import qs.common

// A thick rounded slider (volume, mic, brightness). The filled part carries
// the icon; click the icon to mute. Drag, click anywhere, or scroll.
Item {
    id: root

    property real value: 0              // 0-1, from the system
    property string icon: ""
    property bool muted: false
    property bool canMute: true

    signal moved(real value)
    signal iconClicked()

    // While dragging, show where the finger is, not the system's echo.
    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: Math.max(0, Math.min(1, dragging ? dragValue : value))

    implicitHeight: Style.ccSliderHeight

    function valueAt(x) {
        return Math.max(0, Math.min(1, (x - height / 2) / (width - height)));
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Style.alpha(Colors.textOnSurface, 0.1)

        Rectangle {
            id: fill
            height: parent.height
            width: parent.height + (parent.width - parent.height) * root.shown
            radius: height / 2
            color: root.muted ? Style.alpha(Colors.textOnSurface, 0.28) : Colors.primary

            Behavior on width {
                enabled: !root.dragging
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            root.dragging = true;
            root.dragValue = root.valueAt(mouse.x);
            root.moved(root.dragValue);
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            root.dragValue = root.valueAt(mouse.x);
            root.moved(root.dragValue);
        }
        onReleased: root.dragging = false
        onCanceled: root.dragging = false
        onWheel: wheel => {
            const step = (wheel.angleDelta.y || -wheel.angleDelta.x) / 120 * 0.05;
            root.moved(Math.max(0, Math.min(1, root.value + step)));
        }
    }

    // Icon at the start of the fill: click to mute.
    MouseArea {
        id: iconArea
        width: root.height
        height: root.height
        enabled: root.canMute
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.iconClicked()

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 8
            height: width
            radius: width / 2
            color: Colors.textOnPrimary
            opacity: iconArea.containsMouse ? 0.12 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }

        Icon {
            anchors.centerIn: parent
            name: root.icon
            size: 19
            fill: root.muted ? 0 : 1
            color: root.muted ? Colors.textOnSurfaceVariant : Colors.textOnPrimary
        }
    }

    StyledText {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: root.muted ? "Off" : Math.round(root.shown * 100) + "%"
        role: "label"
        font.features: ({ "tnum": 1 })
        // On the fill when it reaches the number.
        color: fill.width > parent.width - 52 && !root.muted ? Colors.textOnPrimary : Colors.textOnSurfaceVariant
    }
}
