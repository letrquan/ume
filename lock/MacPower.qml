import QtQuick
import QtQuick.Effects
import qs.common

// The mac style's ⏻ in the bottom-right corner. It opens into Sleep,
// Restart and Shut Down, round buttons with their names under them like a
// Mac's (two steps on purpose, so a stray click can't turn the laptop
// off), and closes again by itself after a few seconds.
Item {
    id: root

    property bool open: false
    // 0 → 1 as the picture behind gets bright: darker buttons.
    property real boost: 0
    signal action(string name)      // "suspend" | "reboot" | "poweroff"

    readonly property real button: 40
    readonly property var entries: [
        { name: "suspend", icon: "bedtime", label: "Sleep" },
        { name: "reboot", icon: "restart_alt", label: "Restart" },
        { name: "poweroff", icon: "power_settings_new", label: "Shut Down" }
    ]

    implicitWidth: row.implicitWidth
    implicitHeight: button + 22

    Timer {
        running: root.open
        interval: 6000
        onTriggered: root.open = false
    }

    Row {
        id: row
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 18
        layoutDirection: Qt.RightToLeft

        // ⏻, turning into ✕ while open.
        RoundButton {
            icon: root.open ? "close" : "power_settings_new"
            label: ""
            turn: root.open ? 90 : 0
            onClicked: root.open = !root.open
        }

        Repeater {
            // Right to left: Shut Down next to ⏻, Sleep the furthest.
            model: root.entries.slice().reverse()

            RoundButton {
                required property var modelData
                required property int index
                icon: modelData.icon
                label: modelData.label
                opacity: root.open ? 1 : 0
                visible: opacity > 0.01
                enabled: root.open
                transform: Translate { x: root.open ? 0 : 24 + index * 12 }
                Behavior on opacity {
                    NumberAnimation { duration: Motion.fast + index * 50; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
                }
                onClicked: root.action(modelData.name)
            }
        }
    }

    component RoundButton: Item {
        id: btn
        property string icon: ""
        property string label: ""
        property real turn: 0
        signal clicked()

        width: Math.max(root.button, caption.implicitWidth)
        height: root.button + 22

        Rectangle {
            id: disc
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.button
            height: root.button
            radius: width / 2
            readonly property real a: tap.pressed ? 0.36 : hover.hovered ? 0.28 : 0.18
            color: Qt.rgba(1 - root.boost, 1 - root.boost, 1 - root.boost, a * (1 - root.boost) + (a + 0.2) * root.boost)
            border.color: Qt.rgba(1, 1, 1, 0.22)
            border.width: 1
            scale: tap.pressed ? 0.92 : 1
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on scale {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
            }

            Icon {
                anchors.centerIn: parent
                name: btn.icon
                size: 20
                color: "white"
                rotation: btn.turn
                Behavior on rotation {
                    NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                }
            }

            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: tap; onTapped: btn.clicked() }
        }
        StyledText {
            id: caption
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: disc.bottom
            anchors.topMargin: 5
            visible: btn.label !== ""
            text: btn.label
            color: "white"
            role: "label"
            // A shadow only on a bright picture (none at all on a dark one).
            layer.enabled: root.boost > 0.01
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.6 * root.boost)
                shadowBlur: 0.6
            }
        }
    }
}
