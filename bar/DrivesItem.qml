import QtQuick
import Quickshell
import qs.common
import qs.services

// USB drives plugged in (services/Drives.qml): a USB icon (an SD card's
// when that's all there is), and how many when more than one. Only on the bar while there's one. Click: the popup
// with each drive's size and free space, Open and Eject.
Reveal {
    id: root

    // (`wanted`: the bar's slot reads it, see BarContent.)
    readonly property bool wanted: shown || implicitWidth > 0.5

    anchors.verticalCenter: parent?.verticalCenter
    shown: Drives.count > 0

    Clickable {
        id: button
        spacing: 3
        tip: Drives.drives.length === 1 ? Drives.drives[0].title : Drives.drives.length + " USB drives"
        tipDetail: Drives.drives.map(d => d.title + " · " + d.sizeText
            + (d.mounted && d.used + d.avail > 0 ? " · " + Drives.sizeText(d.avail) + " free" : "")).join("\n")
            + "\nClick: open or eject"
        onClicked: {
            const win = button.QsWindow.window;
            BarPopupState.toggle("drives", win?.screen?.name ?? "",
                                 win ? win.itemRect(button) : Qt.rect(0, 0, 0, 0));
        }

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: Drives.drives.length > 0 && Drives.drives.every(d => d.card) ? "sd_card" : "usb"
            size: 17
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: Drives.count > 1
            text: String(Drives.count)
            role: "body"
            font.features: ({ "tnum": 1 })
        }
    }
}
