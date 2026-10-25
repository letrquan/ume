import QtQuick
import qs.common
import qs.services

// Tailscale: a small lock-in-a-globe, dim while off. Hover: on or off and
// how many devices are online. Click: the control center's Tailscale page.
// Not on the bar by default (Settings → Bar items).
Clickable {
    id: root

    // (`wanted`: the bar's slot reads it, see BarSlot.)
    readonly property bool wanted: Tailscale.installed

    tip: "Tailscale"
    tipDetail: Tailscale.summary
    onClicked: ControlState.toggle("tailscale")

    // Keeps its state fresh while it's on the bar.
    Component.onCompleted: Tailscale.use("bar", true)
    Component.onDestruction: Tailscale.use("bar", false)

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: "vpn_lock"
        size: 16
        fill: Tailscale.running ? 1 : 0
        opacity: Tailscale.running ? 1 : 0.45
        Behavior on opacity {
            NumberAnimation { duration: Motion.normal }
        }
    }
}
