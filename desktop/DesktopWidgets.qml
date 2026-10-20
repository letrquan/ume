import QtQuick
import qs.common

// The cards on the desktop, in Style.desktopWidgets order ("music",
// "system", "calendar"), one under the other. A card only exists while it's
// in the list (so a system card that isn't there reads nothing), and the
// music card only shows while something has a track.
Column {
    id: root

    readonly property var names: Style.desktopWidgets.filter(n => ["music", "system", "calendar"].includes(n))
    // The card that takes clicks (its buttons) while it shows, or null.
    property Item music: null
    readonly property bool anyShown: implicitHeight > 0

    spacing: 12

    Repeater {
        model: root.names

        Loader {
            id: card
            required property string modelData
            visible: status === Loader.Ready && (modelData !== "music" || item.wanted)
            sourceComponent: modelData === "music" ? musicCard : modelData === "system" ? systemCard : calendarCard

            readonly property bool clickable: modelData === "music" && visible
            onClickableChanged: root.music = clickable ? item : (root.music === item ? null : root.music)
            Component.onDestruction: if (root.music === item) root.music = null
        }
    }

    Component { id: musicCard; MusicCard {} }
    Component { id: systemCard; SystemCard {} }
    Component { id: calendarCard; CalendarCard {} }
}
