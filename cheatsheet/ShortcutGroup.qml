import QtQuick
import qs.common

// A titled group of shortcuts ("Windows", "Workspaces"…) on a soft card.
// `shown` (0-1) slides it up and fades it in when the sheet opens.
Item {
    id: root

    // { title, rows }
    required property var group
    property real shown: 1

    // Header + rows + padding; CheatSheetView uses the same sum to split the
    // groups into columns.
    implicitHeight: column.implicitHeight + 16
    opacity: shown

    transform: Translate {
        y: (1 - root.shown) * 14
    }

    // A symbol for the usual groups.
    readonly property string symbol: ({
        "Apps": "apps",
        "Windows": "select_window",
        "Focus": "center_focus_strong",
        "Move windows": "open_with",
        "Monitors": "desktop_windows",
        "Layout": "dashboard",
        "Workspaces": "view_week",
        "Mouse": "mouse",
        "Touchpad gestures": "swipe",
        "Shell": "widgets",
        "Screenshots": "screenshot_region",
        "Media & brightness": "music_note"
    })[group.title] ?? "keyboard"

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: Style.alpha(Colors.surfaceContainerHigh, 0.6)
    }

    Column {
        id: column
        x: 14
        y: 8
        width: parent.width - 28

        Row {
            height: 28
            spacing: 8

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.symbol
                size: 17
                color: Colors.primary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.group.title
                role: "label"
                color: Colors.primary
            }
        }

        Repeater {
            model: root.group.rows

            ShortcutRow {
                required property var modelData
                width: column.width
                row: modelData
            }
        }
    }
}
