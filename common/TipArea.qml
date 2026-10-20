import QtQuick

// A tip on the bar for something that isn't a Clickable (which has its
// own `tip`): put one inside it. Same three properties as Clickable's.
//   TipArea { tip: "Workspace 2"; tipDetail: "foot\nZen" }
HoverHandler {
    id: root

    property string tip: ""
    property string tipDetail: ""
    property string tipShortcut: ""
    // What the tip is placed under (common/Tooltips.qml).
    readonly property Item tipItem: parent

    onHoveredChanged: {
        if (hovered ? Tooltips.hasTip(root) : Tooltips.hovered === root)
            Tooltips.hover(root, hovered);
    }
}
