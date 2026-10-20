import QtQuick
import Quickshell.Services.SystemTray
import qs.common

// Tray icons (Discord, Steam, ...), then a divider. Slides away when there
// are none.
Reveal {
    anchors.verticalCenter: parent?.verticalCenter
    shown: SystemTray.items.values.length > 0

    Row {
        spacing: 10
        leftPadding: 8

        Repeater {
            model: SystemTray.items
            TrayItem {}
        }

        Divider {}
    }
}
