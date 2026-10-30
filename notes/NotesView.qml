import QtQuick
import qs.common
import qs.services

// The notes panel's card (notes/NotesWindow.qml): the list of notes, or
// one note open (Notes.current):
//   list   each note (its kind, name, when; 📌 the one on the desktop),
//          New: Note / Checklist / Drawing
//   note   ‹ back, its title, on the desktop, the on-screen keyboard,
//          delete; then the text (notes/NoteText.qml), the checklist
//          (notes/NoteChecklist.qml) or the drawing page (notes/NoteInk.qml)
// Esc closes (from a note's field: back to the list first).
Item {
    id: root

    property bool shown: false
    // The open note's editor (tests look in).
    readonly property alias editorItem: editor.item
    readonly property var note: Notes.current === "" ? null : Notes.find(Notes.current)
    // Deleting asks twice (a second click within a few seconds).
    property bool armed: false

    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.97
    transformOrigin: Item.TopRight
    Behavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects } }
    Behavior on scale { NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

    // Clicks on the card stay on the card (outside closes the panel).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Glass {
        anchors.fill: parent
        radius: Style.radiusPanel
        color: Style.alpha(Colors.surfaceContainer, Style.notesOpacity)
    }

    focus: true
    Keys.onEscapePressed: Notes.close()

    // ---- Header --------------------------------------------------------------------
    component HeaderButton: Clickable {
        id: headerButton
        property string icon: ""
        property bool lit: false
        anchors.verticalCenter: parent?.verticalCenter
        implicitHeight: 34
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: headerButton.icon
            size: 20
            fill: headerButton.lit ? 1 : 0
            color: headerButton.lit ? Colors.primary : Colors.textOnSurface
        }
    }

    Item {
        id: header
        x: 12
        y: 10
        width: parent.width - 24
        height: 40

        Row {
            id: left
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            HeaderButton {
                visible: root.note !== null
                icon: "chevron_left"
                onClicked: Notes.current = ""
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.note === null
                leftPadding: 6
                text: "Notes"
                role: "headline"
            }
        }

        Row {
            id: right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            HeaderButton {
                visible: root.note !== null
                icon: "push_pin"
                lit: root.note !== null && Notes.desktopNote?.id === root.note.id && Notes.desktopId !== ""
                onClicked: Notes.pin(root.note.id)
            }
            HeaderButton {
                visible: root.note !== null
                icon: root.armed ? "delete_forever" : "delete"
                lit: root.armed
                onClicked: {
                    if (!root.armed) {
                        root.armed = true;
                        disarm.restart();
                        return;
                    }
                    root.armed = false;
                    Notes.remove(root.note.id);
                }
                Timer {
                    id: disarm
                    interval: 3000
                    onTriggered: root.armed = false
                }
            }
            // The shell's on-screen keyboard (it types into this panel).
            HeaderButton {
                icon: "keyboard"
                lit: OskState.open
                onClicked: OskState.toggle()
            }
            HeaderButton {
                icon: "close"
                onClicked: Notes.close()
            }
        }
    }

    // ---- The list --------------------------------------------------------------------
    Item {
        id: listPage
        x: 12
        y: header.y + header.height + 6
        width: parent.width - 24
        height: parent.height - y - 12
        visible: root.note === null

        ListView {
            id: list
            width: parent.width
            height: parent.height - newRow.height - 10
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            // Only while it shows (each change makes its rows again).
            model: listPage.visible ? Notes.notes : []

            delegate: MouseArea {
                id: row
                required property var modelData
                width: list.width
                height: 58
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Notes.current = modelData.id

                Rectangle {
                    anchors.fill: parent
                    radius: Style.inner(Style.radiusPanel, 12)
                    color: Colors.textOnSurface
                    opacity: row.pressed ? Style.pressTint : row.containsMouse ? Style.hoverTint : 0.04
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }
                Icon {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    name: Notes.iconOf(row.modelData)
                    size: 22
                    color: Colors.primary
                }
                Column {
                    x: 48
                    width: parent.width - 48 - 40
                    anchors.verticalCenter: parent.verticalCenter
                    StyledText {
                        width: parent.width
                        text: Notes.label(row.modelData)
                        role: "title"
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        role: "caption"
                        color: Colors.textOnSurfaceVariant
                        elide: Text.ElideRight
                        text: {
                            const n = row.modelData;
                            const when = n.updated > 0 ? Notes.ago(n.updated) : "";
                            const what = n.kind === "list" ? n.items.filter(i => i.done).length + " of " + n.items.length + " done"
                                       : n.kind === "ink" ? (n.strokes.length === 0 ? "Empty page" : n.strokes.length + " strokes")
                                       : n.text.trim().split("\n").slice(n.title.trim() === "" ? 1 : 0).join(" ").slice(0, 80);
                            return [when, what].filter(x => x !== "").join(" · ");
                        }
                    }
                }
                Icon {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Notes.desktopNote?.id === row.modelData.id
                    name: "push_pin"
                    size: 16
                    color: Colors.textOnSurfaceVariant
                }
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - 40
                visible: Notes.notes.length === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "No notes yet. Start one below: write, tick things off, or draw with the pen."
                color: Colors.textOnSurfaceVariant
            }
        }

        // New: Note / Checklist / Drawing.
        Row {
            id: newRow
            anchors.bottom: parent.bottom
            width: parent.width
            height: 44
            spacing: 8

            Repeater {
                model: [
                    { kind: "text", icon: "edit_note", label: "Note" },
                    { kind: "list", icon: "checklist", label: "Checklist" },
                    { kind: "ink", icon: "draw", label: "Drawing" }
                ]
                MouseArea {
                    id: newButton
                    required property var modelData
                    width: (newRow.width - 16) / 3
                    height: newRow.height
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notes.current = Notes.add(modelData.kind)

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Style.alpha(Colors.primary, newButton.pressed ? 0.3 : newButton.containsMouse ? 0.24 : 0.16)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: newButton.modelData.icon
                            size: 18
                            color: Colors.primary
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: newButton.modelData.label
                            weight: 650
                            color: Colors.primary
                        }
                    }
                }
            }
        }
    }

    // ---- One note ----------------------------------------------------------------------
    Loader {
        id: editor
        x: 12
        y: header.y + header.height + 6
        width: parent.width - 24
        height: parent.height - y - 12
        active: root.note !== null
        // A new editor for each note (each loads its note once, then writes).
        property string forId: ""
        sourceComponent: root.note?.kind === "list" ? checklist : root.note?.kind === "ink" ? drawing : textNote
        onActiveChanged: forId = active ? Notes.current : ""
    }
    Connections {
        target: Notes
        function onCurrentChanged() {
            // Another note: a fresh editor.
            editor.active = false;
            editor.active = Qt.binding(() => root.note !== null);
        }
    }

    Component { id: textNote; NoteText { noteId: Notes.current } }
    Component { id: checklist; NoteChecklist { noteId: Notes.current } }
    Component { id: drawing; NoteInk { noteId: Notes.current } }
}
