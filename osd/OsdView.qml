import QtQuick
import qs.common

// The OSD pill: a shape with an icon that morphs when the kind changes.
//  - Levels (volume, mic, brightness): the shape turns with the level, then
//    the device name, a level bar and the number.
//  - States (Caps Lock, Num Lock, Wi-Fi, Bluetooth, power mode, Silent,
//    keyboard layout, tiling layout, typing language): the name and a chip
//    with On / Off (or the mode or layout name, EN / VI); the shape turns
//    into place and fills when it's on.
// Plain QtQuick, so it can be previewed outside the shell.
Item {
    id: root

    property string kind: "volume"      // volume | mic | brightness | capslock | numlock | wifi | bluetooth | power | dnd | layout | tiling | ime
    property real value: 0              // 0-1 (levels)
    property bool muted: false          // levels
    property string label: ""
    property bool isState: false
    property bool active: false         // states: on
    property string detail: ""          // states: the word in the chip
    property string tilingIcon: "dashboard"     // tiling: the layout's icon

    readonly property real level: Math.max(0, Math.min(1, value))
    // Dim shape: muted level, or a state that is off.
    readonly property bool dim: isState ? !active : muted

    readonly property string icon: {
        switch (kind) {
        case "brightness":
            return level < 0.34 ? "brightness_low" : level < 0.67 ? "brightness_medium" : "brightness_high";
        case "mic":
            return muted ? "mic_off" : "mic";
        case "capslock":
            return "keyboard_capslock";
        case "numlock":
            return "dialpad";
        case "wifi":
            return active ? "wifi" : "wifi_off";
        case "bluetooth":
            return active ? "bluetooth" : "bluetooth_disabled";
        case "power":
            return detail === "Saver" ? "eco" : detail === "Performance" ? "bolt" : "balance";
        case "dnd":
            return active ? "do_not_disturb_on" : "notifications";
        case "layout":
            return "keyboard";
        case "tiling":
            return tilingIcon;
        case "ime":
            return detail === "VI" ? "translate" : "keyboard";
        }
        return muted || level === 0 ? "volume_off"
             : level < 0.34 ? "volume_mute"
             : level < 0.67 ? "volume_down" : "volume_up";
    }

    readonly property string shapeName: {
        switch (kind) {
        case "brightness": return "Sunny";
        case "mic": return "Clover4Leaf";
        case "capslock": return "Arch";
        case "numlock": return "Square";
        case "wifi": return "Fan";
        case "bluetooth": return "Gem";
        case "power": return detail === "Saver" ? "Clover8Leaf" : detail === "Performance" ? "SoftBurst" : "Cookie6Sided";
        case "dnd": return "Puffy";
        case "layout": return "Pill";
        case "tiling": return "Cookie4Sided";
        case "ime": return detail === "VI" ? "Flower" : "Cookie12Sided";
        }
        return "Cookie9Sided";
    }

    implicitWidth: Style.osdWidth
    implicitHeight: Style.osdHeight

    // mango doesn't blur the OSD's window (it can't fade its blur): the
    // frost is the shell's own, so it comes and goes with the pill. Where
    // the pill is on the screen comes from OsdWindow.
    property point screenAt: Qt.point(0, 0)
    property size screenSize: Qt.size(0, 0)
    WallpaperFrost {
        anchors.fill: parent
        at: root.screenAt
        screenWidth: root.screenSize.width
        screenHeight: root.screenSize.height
        radius: height / 2
        visible: root.screenSize.width > 0
    }
    Glass {
        anchors.fill: parent
        radius: height / 2
    }

    Item {
        id: badge
        x: (root.height - height) / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32

        Shape {
            anchors.fill: parent
            shape: root.shapeName
            color: root.dim ? Style.alpha(Colors.textOnSurface, 0.16) : Colors.primary
            rotation: root.isState ? (root.active ? 0 : -45) : root.level * 120

            Behavior on rotation {
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Icon {
            anchors.centerIn: parent
            name: root.icon
            size: 18
            fill: root.dim ? 0 : 1
            color: root.dim ? Colors.textOnSurfaceVariant : Colors.textOnPrimary
        }
    }

    // Everything right of the shape; levels and states cross-fade.
    Item {
        id: body
        anchors.left: badge.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        // ---- Levels: name, bar, number -------------------------------------------
        Item {
            anchors.fill: parent
            opacity: root.isState ? 0 : 1
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - number.width - 12
                spacing: 6

                StyledText {
                    width: parent.width
                    text: root.isState ? "" : root.label
                    role: "caption"
                    color: Colors.textOnSurfaceVariant
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: track
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Style.alpha(Colors.textOnSurface, 0.14)

                    Rectangle {
                        width: Math.max(track.height, track.width * root.level)
                        height: track.height
                        radius: track.radius
                        color: root.muted ? Style.alpha(Colors.textOnSurface, 0.3) : Colors.primary

                        Behavior on width {
                            NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                        }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                }
            }

            StyledText {
                id: number
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                horizontalAlignment: Text.AlignRight
                text: root.muted ? "Off" : Math.round(root.level * 100)
                weight: 700
                font.features: ({ "tnum": 1 })
                color: root.muted ? Colors.textOnSurfaceVariant : Colors.textOnSurface
            }
        }

        // ---- States: name and a chip -------------------------------------------------
        Item {
            anchors.fill: parent
            opacity: root.isState ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            }

            StyledText {
                anchors.left: parent.left
                anchors.right: chip.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.isState ? root.label : ""
                role: "title"
                elide: Text.ElideRight
            }

            Rectangle {
                id: chip
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(chipText.implicitWidth + 22, parent.width * 0.6)
                height: 26
                radius: height / 2
                color: root.active ? Colors.primary : "transparent"
                border.width: root.active ? 0 : 1.5
                border.color: Style.alpha(Colors.textOnSurface, 0.3)

                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on width {
                    NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
                }

                StyledText {
                    id: chipText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, chip.width - 16)
                    horizontalAlignment: Text.AlignHCenter
                    text: root.detail
                    role: "label"
                    elide: Text.ElideRight
                    color: root.active ? Colors.textOnPrimary : Colors.textOnSurfaceVariant
                }
            }
        }
    }
}
