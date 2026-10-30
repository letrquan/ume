import QtQuick
import qs.common
import qs.services

// A text note in the notes panel: its title and the text under it. Read
// from the note once when it opens; then every change is written back
// (Notes.update; the file a moment later), the word an input method is
// still composing included (notes/Composing.qml).
Item {
    id: root

    required property string noteId

    function keepAll() {
        titleWord.keep();
        bodyWord.keep();
    }
    Connections {
        target: Notes
        function onClosing() {
            root.keepAll();
        }
    }

    Component.onCompleted: {
        const n = Notes.find(noteId);
        title.text = n?.title ?? "";
        body.text = n?.text ?? "";
        // A new note: straight to typing.
        if ((n?.text ?? "") === "" && (n?.title ?? "") === "")
            body.forceActiveFocus();
    }

    TextInput {
        id: title
        x: 6
        width: parent.width - 12
        height: 34
        verticalAlignment: TextInput.AlignVCenter
        color: Colors.textOnSurface
        selectionColor: Style.alpha(Colors.primary, 0.4)
        font.family: Style.font
        font.pixelSize: Style.textSize("headline")
        font.variableAxes: ({ "wght": 700, "ROND": 100 })
        clip: true
        onAccepted: body.forceActiveFocus()
        Keys.onDownPressed: body.forceActiveFocus()

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: titleWord.value === ""
            text: "Title"
            role: "headline"
            color: Style.alpha(Colors.textOnSurfaceVariant, 0.7)
        }
    }
    Composing {
        id: titleWord
        field: title
        onValueChanged: Notes.update(root.noteId, { title: value })
    }

    Rectangle {
        y: title.height + 6
        x: 6
        width: parent.width - 12
        height: 1
        color: Style.alpha(Colors.textOnSurface, 0.1)
    }

    Flickable {
        id: scroller
        y: title.height + 14
        width: parent.width
        height: parent.height - y
        contentHeight: Math.max(body.implicitHeight + 20, height)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // The cursor stays in sight while typing.
        function follow(r) {
            if (r.y < contentY)
                contentY = r.y;
            else if (r.y + r.height > contentY + height)
                contentY = r.y + r.height - height + 8;
        }

        TextEdit {
            id: body
            x: 6
            width: scroller.width - 12
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            color: Colors.textOnSurface
            selectionColor: Style.alpha(Colors.primary, 0.4)
            font.family: Style.font
            font.pixelSize: Style.textSize("body") + 1
            onCursorRectangleChanged: scroller.follow(cursorRectangle)

            StyledText {
                visible: bodyWord.value === ""
                text: "Write something…"
                color: Style.alpha(Colors.textOnSurfaceVariant, 0.7)
            }
        }
        // A click under the text: the cursor at its end.
        MouseArea {
            y: body.implicitHeight
            width: parent.width
            height: Math.max(0, scroller.contentHeight - body.implicitHeight)
            cursorShape: Qt.IBeamCursor
            onClicked: {
                body.forceActiveFocus();
                body.cursorPosition = body.length;
            }
        }
    }
    Composing {
        id: bodyWord
        field: body
        onValueChanged: Notes.update(root.noteId, { text: value })
    }
}
