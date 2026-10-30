import QtQuick
import qs.common
import qs.services
import qs.ink
import "../ink/ink.js" as InkData

// A note on the desktop (services/Notes.qml: the one pinned with 📌 in the
// notes panel, or the newest): its title and
//   text   its first lines
//   list   what's still to do (tick one here: ○), and how many are done
//   ink    the drawing, made to fit
// A click anywhere else opens the notes panel on it (typing happens there:
// the desktop never takes the keyboard). No note yet: a "New note" card.
DesktopCard {
    id: root

    readonly property var note: Notes.revision >= 0 ? Notes.desktopNote : null
    readonly property int maxItems: 7
    // The screen this card is on (the panel opens there).
    property string screenName: ""

    implicitWidth: 320
    implicitHeight: body.implicitHeight + padding * 2

    // Behind everything in the card: open the panel.
    MouseArea {
        anchors.fill: parent
        anchors.margins: -root.padding
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.note)
                Notes.show(root.note.id, root.screenName);
            else
                Notes.show(Notes.add("text"), root.screenName);
        }
    }

    Column {
        id: body
        width: parent.width
        spacing: 8

        Row {
            width: parent.width
            spacing: 8
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.note ? Notes.iconOf(root.note) : "edit_note"
                size: 20
                color: Colors.primary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 28
                text: root.note ? Notes.label(root.note) : "Notes"
                role: "title"
                elide: Text.ElideRight
            }
        }

        // No note yet.
        StyledText {
            visible: root.note === null
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Click to write a note, a checklist or draw with the pen."
            color: Colors.textOnSurfaceVariant
        }

        // Text: its first lines (after the title line when there's no title).
        StyledText {
            visible: root.note?.kind === "text" && text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 9
            elide: Text.ElideRight
            text: {
                const n = root.note;
                if (n?.kind !== "text")
                    return "";
                const lines = n.text.split("\n");
                return (n.title.trim() === "" ? lines.slice(1) : lines).join("\n").trim();
            }
            color: Colors.textOnSurface
        }

        // Checklist: what's left, each one tickable here.
        Column {
            visible: root.note?.kind === "list"
            width: parent.width
            spacing: 2

            Repeater {
                model: root.note?.kind === "list" ? root.note.items.filter(i => !i.done).slice(0, root.maxItems) : []
                Item {
                    id: line
                    required property var modelData
                    width: parent.width
                    height: 30

                    MouseArea {
                        id: tick
                        width: 30
                        height: parent.height
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notes.toggleItem(root.note.id, line.modelData.id)
                        Rectangle {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            radius: 9
                            color: tick.pressed ? Colors.primary : "transparent"
                            border.width: 2
                            border.color: Style.alpha(Colors.textOnSurface, 0.5)
                        }
                    }
                    StyledText {
                        x: 34
                        width: parent.width - 34
                        anchors.verticalCenter: parent.verticalCenter
                        text: line.modelData.text
                        elide: Text.ElideRight
                    }
                }
            }
            StyledText {
                readonly property var items: root.note?.kind === "list" ? root.note.items : []
                readonly property int toDo: items.filter(i => !i.done).length
                readonly property int finished: items.length - toDo
                visible: text !== ""
                x: 4
                text: [toDo > root.maxItems ? (toDo - root.maxItems) + " more" : "",
                       finished > 0 ? finished + " done" : "",
                       items.length === 0 ? "Nothing on it yet" : toDo === 0 ? "All done" : ""].filter(s => s !== "").join(" · ")
                role: "caption"
                color: Colors.textOnSurfaceVariant
            }
        }

        // Drawing: on its paper, made to fit the card.
        Rectangle {
            id: sheet
            visible: root.note?.kind === "ink"
            readonly property real pageW: Math.max(1, root.note?.w || 400)
            readonly property real pageH: Math.max(1, root.note?.h || 300)
            readonly property real k: width / pageW
            width: parent.width
            height: visible ? Math.min(pageH * k, 260) : 0
            radius: 12
            color: "#fbfaf5"
            clip: true

            InkMarks {
                width: sheet.pageW
                height: sheet.pageH
                scale: sheet.k
                transformOrigin: Item.TopLeft
                strokes: root.note?.kind === "ink" ? root.inkStrokes : []
            }
        }
    }

    // The note's strokes with their shapes made again (they're kept as
    // points): only when that drawing changed, not for every change of any
    // note (typing in another one).
    readonly property string inkKey: root.note?.kind === "ink" ? root.note.id + ":" + root.note.updated : ""
    property var inkStrokes: []
    function remakeInk() {
        inkStrokes = root.note?.kind === "ink" ? root.note.strokes.map(s => InkData.made(s)) : [];
    }
    onInkKeyChanged: remakeInk()
    Component.onCompleted: remakeInk()
}
