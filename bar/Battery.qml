import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.common
import qs.services

// Battery pill with the percentage inside. A bolt slides in while charging,
// hovering shows the time left. Red at Style.batteryLow and below.
Clickable {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property real fraction: device?.percentage ?? 0     // 0-1
    readonly property int percent: Math.round(fraction * 100)
    readonly property bool charging: device?.state === UPowerDeviceState.Charging
                                     || device?.state === UPowerDeviceState.PendingCharge
    readonly property bool low: !charging && percent <= Style.batteryLow
    readonly property real seconds: charging ? (device?.timeToFull ?? 0) : (device?.timeToEmpty ?? 0)
    readonly property color fillColor: low ? Colors.error : Colors.primary
    readonly property color fillText: low ? Colors.textOnError : Colors.textOnPrimary

    function duration(s) {
        const h = Math.floor(s / 3600);
        const m = Math.round((s % 3600) / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }

    // Only on laptops. (`wanted`: the bar's slot reads it, see BarContent.)
    readonly property bool wanted: device?.isLaptopBattery ?? false

    visible: wanted
    spacing: 2
    // (The time left already slides out next to the pill.)
    tip: "Battery " + root.percent + "%" + (root.charging ? " · charging"
        : root.device?.state === UPowerDeviceState.FullyCharged ? " · full" : "")
    tipDetail: "Power mode: " + (PowerProfiles.profile === PowerProfile.PowerSaver ? "Saver"
                                 : PowerProfiles.profile === PowerProfile.Performance ? "Performance" : "Balanced")
    // Click: the battery popup right under it (charge over the last hours,
    // health; Style.batteryPopup, off = the control center as before);
    // right click: the control center.
    function route(button) {
        const win = root.QsWindow.window;
        if (button === Qt.LeftButton && Style.batteryPopup)
            BarPopupState.toggle("battery", win?.screen?.name ?? "", win ? win.itemRect(root) : Qt.rect(0, 0, 0, 0));
        else
            ControlState.toggle("main");
    }
    onClicked: mouse => route(mouse.button)

    Reveal {
        anchors.verticalCenter: parent.verticalCenter
        shown: root.charging

        Icon {
            name: "bolt"
            size: 16
            color: Colors.primary
        }
    }

    Item {
        id: pill

        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 34
        implicitHeight: 16

        Rectangle {
            id: track
            anchors.fill: parent
            radius: height / 2
            color: Style.alpha(Colors.textOnSurface, 0.16)
        }

        // Number over the empty part of the pill (red when low, since the
        // fill is only a sliver then).
        StyledText {
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            text: root.percent
            role: "caption"
            font.features: ({ "tnum": 1 })
            weight: 700
            color: root.low ? Colors.error : Colors.textOnSurface

            Behavior on color { ColorAnimation { duration: Motion.normal } }
        }

        // The filled part, as wide as the charge really is (a sliver of the
        // pill's rounded end when nearly empty), with the same number in the
        // "on fill" color: the digits change color exactly where the fill
        // ends, even halfway through one.
        Item {
            width: Math.max(2, track.width * root.fraction)
            height: track.height
            clip: true

            Behavior on width {
                NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }

            Rectangle {
                width: track.width
                height: track.height
                radius: track.radius
                color: root.fillColor

                Behavior on color { ColorAnimation { duration: Motion.normal } }
            }

            StyledText {
                width: track.width
                height: track.height
                horizontalAlignment: Text.AlignHCenter
                text: root.percent
                role: "caption"
                font.features: ({ "tnum": 1 })
                weight: 700
                color: root.fillText
            }
        }
    }

    Reveal {
        anchors.verticalCenter: parent.verticalCenter
        shown: root.containsMouse && root.seconds > 0

        StyledText {
            leftPadding: 4
            text: root.duration(root.seconds) + (root.charging ? " to full" : " left")
            color: Colors.textOnSurfaceVariant
        }
    }
}
