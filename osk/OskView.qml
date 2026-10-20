import QtQuick
import qs.common
import qs.services
import "layouts.js" as Layouts

// The keyboard itself: glass like the dock, four rows of keys
// (osk/layouts.js: letters, or ?123 for digits and symbols), sliding up
// from the bottom edge. Centered, at most Style.oskMaxWidth wide.
Item {
    id: root

    property bool shown: false
    readonly property alias card: card
    // How far the card is slid down (0 when up). OskWindow's touch area
    // follows it: Quickshell's Region only re-reads an item's x/y/size, not
    // a Translate, so `Region { item: card }` stayed where the card was
    // when the window opened (below the screen) and every touch went
    // through the keyboard to whatever was under it.
    readonly property real slideY: slide.y

    readonly property int pad: 8    // glass edge -> keys
    readonly property int gap: 6    // between keys
    readonly property var rows: Layouts.rows(OskState.page)

    Glass {
        id: card

        width: Math.min(root.width - Style.marginEnds * 2, Style.oskMaxWidth)
        height: Style.oskHeight
        x: Math.round((root.width - width) / 2)
        radius: Style.oskKeyRadius + root.pad
        color: Style.alpha(Colors.surfaceContainer, Style.oskOpacity)

        transform: Translate {
            id: slide
            y: root.shown ? 0 : card.height + Style.marginEdge

            Behavior on y {
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            }
        }

        // Each key gets its share of the row (in units, Layouts.units per
        // row) and draws itself gap / 2 inside it.
        Column {
            id: keys

            readonly property real unit: width / Layouts.units
            readonly property real rowHeight: height / root.rows.length

            anchors.fill: parent
            anchors.margins: root.pad - root.gap / 2

            Repeater {
                model: root.rows

                Row {
                    id: row
                    required property var modelData

                    Repeater {
                        model: row.modelData

                        OskKey {
                            required property var modelData
                            key: modelData
                            gap: root.gap
                            width: modelData.w * keys.unit
                            height: keys.rowHeight
                        }
                    }
                }
            }
        }
    }
}
