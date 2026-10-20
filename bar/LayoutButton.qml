import QtQuick
import qs.common
import qs.services

// The workspace's tiling layout (dwindle, scroller, monocle...) as an icon;
// hovering slides out its name. Click: the next layout (mango's
// circle_layout, same as Super+Alt+J).
Clickable {
    id: root

    required property var mango     // MangoMonitor of this screen

    readonly property string symbol: mango?.layout ?? ""
    // Not known yet (mango not answering): nothing to show.
    readonly property bool wanted: symbol !== ""

    visible: wanted
    spacing: 0
    tip: "Next tiling layout"
    tipShortcut: "func:switch_layout"
    onClicked: Tiling.next()

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: Tiling.icon(root.symbol)
        color: Colors.textOnSurfaceVariant
    }

    Reveal {
        anchors.verticalCenter: parent.verticalCenter
        shown: root.containsMouse

        StyledText {
            leftPadding: 5
            text: Tiling.name(root.symbol)
            color: Colors.textOnSurfaceVariant
        }
    }
}
