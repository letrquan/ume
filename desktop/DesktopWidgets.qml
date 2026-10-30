import QtQuick
import qs.common

// The cards on the desktop, in Style.desktopWidgets order ("music",
// "system", "calendar", "notes"), one under the other. A card only exists
// while it's in the list (so a system card that isn't there reads nothing),
// and the music card only shows while something has a track.
Column {
    id: root

    readonly property var names: Style.desktopWidgets.filter(n => ["music", "system", "calendar", "notes"].includes(n))
    // The card that takes clicks (its buttons) while it shows, or null.
    property Item music: null
    // The notes card takes clicks too (tick an item, open the panel).
    property Item notes: null
    property string screenName: ""
    readonly property bool anyShown: implicitHeight > 0

    spacing: 12

    Repeater {
        model: root.names

        Loader {
            id: card
            required property string modelData
            visible: status === Loader.Ready && (modelData !== "music" || item.wanted)
            sourceComponent: modelData === "music" ? musicCard : modelData === "system" ? systemCard
                           : modelData === "notes" ? notesCard : calendarCard

            readonly property bool clickable: modelData === "music" && visible
            onClickableChanged: root.music = clickable ? item : (root.music === item ? null : root.music)
            readonly property bool notesShown: modelData === "notes" && visible
            onNotesShownChanged: root.notes = notesShown ? item : (root.notes === item ? null : root.notes)
            Component.onDestruction: {
                if (root.music === item)
                    root.music = null;
                if (root.notes === item)
                    root.notes = null;
            }
        }
    }

    Component { id: musicCard; MusicCard {} }
    Component { id: systemCard; SystemCard {} }
    Component { id: calendarCard; CalendarCard {} }
    Component { id: notesCard; NotesCard { screenName: root.screenName } }
}
