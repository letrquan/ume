import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

// The window the bar's tips are drawn in (TooltipView): a see-through
// strip across the top of the screen, as tall as the bar plus the tallest
// tip, that never takes a click (empty mask). Its own layer, so mango
// blurs behind the tip like behind the islands; a PopupWindow wouldn't be
// blurred. Made only while tips are about (Tooltips.mapped).
PanelWindow {
    id: root

    required property ShellScreen modelData

    screen: modelData
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Style.marginEdge + Style.islandHeight + Style.tooltipGap + 150
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}

    WlrLayershell.namespace: "mine-tooltip"
    WlrLayershell.layer: WlrLayer.Top

    TooltipView {
        anchors.fill: parent
    }
}
