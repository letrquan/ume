import QtQuick
import qs.common
import qs.services

// Your phone (KDE Connect): its battery, a bolt while charging, red when
// low. On the bar only while a phone is connected (or asking to pair);
// with Style.barHideUnused off, also while it's paired but away, faded.
// Click: the control center's Phone page.
Reveal {
    id: root

    // (`wanted`: the bar's slot reads it, see BarContent.)
    readonly property bool wanted: shown || implicitWidth > 0.5

    anchors.verticalCenter: parent?.verticalCenter
    shown: Phone.device !== null && (Phone.connected || Phone.pairing || !Style.barHideUnused)

    // Keeps the phone's state fresh while it's on the bar.
    Component.onCompleted: Phone.use(true)
    Component.onDestruction: Phone.use(false)

    Clickable {
        spacing: 3
        opacity: Phone.connected ? 1 : 0.45
        tip: Phone.device?.name ?? "Phone"
        tipDetail: Phone.summary
        onClicked: ControlState.toggle("phone")

        Behavior on opacity {
            NumberAnimation { duration: Motion.normal }
        }

        // Always the phone (a bolt here would read as the laptop's battery).
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: Phone.glyphFor(Phone.device)
            size: 16
            fill: Phone.connected ? 1 : 0
            color: Phone.low ? Colors.error : Colors.textOnSurface
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: Phone.charge >= 0
            text: Phone.charge + "%"
            role: "body"
            font.features: ({ "tnum": 1 })
            color: Phone.low ? Colors.error : Colors.textOnSurface
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: Phone.charging
            name: "bolt"
            size: 12
            color: Colors.primary
        }
    }
}
