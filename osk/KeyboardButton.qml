import QtQuick
import qs.common
import qs.services

// Bar item "keyboard": the on-screen keyboard for touch, without folding
// the screen back (Settings → Bar items). Lit while it shows. With
// Style.barHideUnused it's only on the bar in tablet mode or while the
// keyboard is up.
Reveal {
    id: root

    // (`wanted`: the bar's slot reads it, see BarContent.)
    readonly property bool wanted: shown || implicitWidth > 0.5

    anchors.verticalCenter: parent?.verticalCenter
    shown: !Style.barHideUnused || TabletMode.tablet || OskState.open

    Clickable {
        tip: OskState.open ? "Hide the on-screen keyboard" : "On-screen keyboard"
        onClicked: OskState.toggle()

        Icon {
            name: OskState.open ? "keyboard_hide" : "keyboard"
            fill: OskState.open ? 1 : 0
            color: OskState.open ? Colors.primary : Colors.textOnSurface
        }
    }
}
