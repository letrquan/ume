import QtQuick
import qs.common
import qs.services

// A checklist in the notes panel: its title, the items to do, "Add an
// item", and the ticked ones under "N done" (folded away with
// Style.notesCollapseDone; click to show them).
//   ○ / ✓     tick (it goes to the top of the done ones) or untick
//   ⠿         drag to reorder (made for a finger or the pen too)
//   Enter     a new item under this one; ⌫ in an empty one deletes it
//   ×         delete
// The panel keeps its own lists while the note is open (so typing is never
// interrupted) and writes them back on every change (Notes.setItems), the
// word an input method is still composing included.
Item {
    id: root

    required property string noteId
    readonly property int rowHeight: 44
    property bool showDone: !Style.notesCollapseDone

    ListModel { id: todo }
    ListModel { id: done }
    // For the tests: the lists and their rows.
    readonly property alias todoList: todo
    readonly property alias doneList: done
    function todoRow(i) {
        return todoRows.itemAt(i);
    }
    readonly property alias adderField: adder

    function collect() {
        const out = [];
        for (let i = 0; i < todo.count; i++)
            out.push({ id: todo.get(i).iid, text: todo.get(i).text, done: false });
        for (let i = 0; i < done.count; i++)
            out.push({ id: done.get(i).iid, text: done.get(i).text, done: true });
        return out;
    }
    // (Not while the lists are being filled: half of it would be written.)
    property bool loading: true
    function save() {
        if (!loading && Notes.find(noteId))
            Notes.setItems(noteId, collect());
    }

    Component.onCompleted: {
        const n = Notes.find(noteId);
        title.text = n?.title ?? "";
        for (const it of n?.items ?? [])
            (it.done ? done : todo).append({ iid: it.id, text: it.text, done: it.done });
        loading = false;
        // Nothing on it yet: straight to adding.
        if ((n?.items ?? []).length === 0)
            adder.forceActiveFocus();
    }
    Connections {
        target: Notes
        function onClosing() {
            root.keepWords();
        }
    }
    signal keepWords()
    onKeepWords: {
        titleWord.keep();
        addWord.keep();
    }

    function newId() {
        return "i" + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
    }

    // Ticked / unticked: from one list to the other.
    function toggle(list, index) {
        const e = list.get(index);
        const item = { iid: e.iid, text: e.text, done: list === todo };
        list.remove(index);
        if (list === todo)
            done.insert(0, item);
        else
            todo.append(item);
        save();
    }
    // A new empty item after `index` in `list`, and the cursor in it.
    function insertAfter(list, index, text) {
        list.insert(index + 1, { iid: newId(), text: text ?? "", done: list === done });
        save();
        Qt.callLater(() => (list === todo ? todoRows : doneRows).itemAt(index + 1)?.focusInput(0));
    }
    function removeAt(list, index, focusBefore) {
        list.remove(index);
        save();
        if (focusBefore) {
            const rows = list === todo ? todoRows : doneRows;
            Qt.callLater(() => {
                const r = rows.itemAt(Math.max(0, index - 1));
                if (r)
                    r.focusInput(-1);
                else
                    adder.forceActiveFocus();
            });
        }
    }

    // ---- One item ------------------------------------------------------------------
    component ItemRow: Item {
        id: row

        required property int index
        required property string iid
        required property string text
        required property bool done
        property ListModel list: null
        property Item rowsColumn: null

        // While dragging: how far from its place it is held.
        property real held: 0
        readonly property bool dragging: handle.pressed
        z: dragging ? 2 : 0
        width: parent?.width ?? 0
        height: root.rowHeight
        transform: Translate { y: row.held }

        readonly property alias handleItem: handle
        readonly property alias checkItem: check
        readonly property alias inputItem: input

        function focusInput(at) {
            input.forceActiveFocus();
            input.cursorPosition = at < 0 ? input.length : at;
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            radius: 12
            color: Colors.textOnSurface
            opacity: row.dragging ? 0.12 : hover.hovered || input.activeFocus ? 0.06 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        HoverHandler { id: hover }

        // ⠿ drag to reorder.
        MouseArea {
            id: handle
            width: 30
            height: parent.height
            preventStealing: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real startY: 0
            onPressed: mouse => startY = mapToItem(row.rowsColumn, mouse.x, mouse.y).y
            onPositionChanged: mouse => {
                const y = mapToItem(row.rowsColumn, mouse.x, mouse.y).y;
                const target = Math.max(0, Math.min(row.list.count - 1, Math.round(row.index + (y - startY) / root.rowHeight)));
                if (target !== row.index) {
                    startY += (target - row.index) * root.rowHeight;
                    row.list.move(row.index, target, 1);
                }
                row.held = y - startY;
            }
            onReleased: {
                row.held = 0;
                root.save();
            }
            onCanceled: row.held = 0

            Icon {
                anchors.centerIn: parent
                name: "drag_indicator"
                size: 18
                color: Colors.textOnSurfaceVariant
                opacity: hover.hovered || handle.pressed ? 1 : 0.45
            }
        }

        // ○ / ✓
        MouseArea {
            id: check
            x: 30
            width: 36
            height: parent.height
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle(row.list, row.index)

            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: 11
                color: row.done ? Colors.primary : "transparent"
                border.width: row.done ? 0 : 2
                border.color: Style.alpha(Colors.textOnSurface, 0.45)
                Icon {
                    anchors.centerIn: parent
                    visible: row.done
                    name: "check"
                    size: 16
                    color: Colors.textOnPrimary
                }
            }
        }

        TextInput {
            id: input
            x: 70
            width: parent.width - x - 36
            anchors.verticalCenter: parent.verticalCenter
            color: row.done ? Colors.textOnSurfaceVariant : Colors.textOnSurface
            selectionColor: Style.alpha(Colors.primary, 0.4)
            font.family: Style.font
            font.pixelSize: Style.textSize("body") + 1
            font.strikeout: row.done
            clip: true
            Component.onCompleted: text = row.text
            onAccepted: {
                word.keep();
                root.insertAfter(row.list, row.index, "");
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Backspace && word.value === "") {
                    root.removeAt(row.list, row.index, true);
                    event.accepted = true;
                }
            }
        }
        Composing {
            id: word
            field: input
            onValueChanged: {
                if (row.list && row.index >= 0 && row.index < row.list.count && row.list.get(row.index).iid === row.iid
                        && row.list.get(row.index).text !== value) {
                    row.list.setProperty(row.index, "text", value);
                    root.save();
                }
            }
        }
        Connections {
            target: root
            function onKeepWords() {
                word.keep();
            }
        }

        // × delete.
        MouseArea {
            anchors.right: parent.right
            width: 36
            height: parent.height
            cursorShape: Qt.PointingHandCursor
            onClicked: root.removeAt(row.list, row.index, false)
            Icon {
                anchors.centerIn: parent
                name: "close"
                size: 18
                color: Colors.textOnSurfaceVariant
                opacity: hover.hovered || input.activeFocus ? 0.9 : 0.3
            }
        }
    }

    // ---- The page ----------------------------------------------------------------------
    Flickable {
        id: scroller
        anchors.fill: parent
        contentHeight: page.implicitHeight + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: !todoRows.anyDragging && !doneRows.anyDragging

        Column {
            id: page
            width: scroller.width

            TextInput {
                id: title
                x: 6
                width: parent.width - 12
                height: 40
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.textOnSurface
                selectionColor: Style.alpha(Colors.primary, 0.4)
                font.family: Style.font
                font.pixelSize: Style.textSize("headline")
                font.variableAxes: ({ "wght": 700, "ROND": 100 })
                clip: true
                onAccepted: adder.forceActiveFocus()

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: titleWord.value === ""
                    text: "Checklist"
                    role: "headline"
                    color: Style.alpha(Colors.textOnSurfaceVariant, 0.7)
                }
            }
            Composing {
                id: titleWord
                field: title
                onValueChanged: Notes.update(root.noteId, { title: value })
            }

            Column {
                id: todoColumn
                width: parent.width
                move: Transition {
                    NumberAnimation { properties: "y"; duration: 160; easing.type: Easing.OutCubic }
                }
                Repeater {
                    id: todoRows
                    model: todo
                    readonly property bool anyDragging: {
                        count;
                        for (let i = 0; i < count; i++)
                            if (itemAt(i)?.dragging)
                                return true;
                        return false;
                    }
                    ItemRow {
                        list: todo
                        rowsColumn: todoColumn
                    }
                }
            }

            // Add an item: Enter adds it and stays here for the next one.
            Item {
                width: parent.width
                height: root.rowHeight

                Icon {
                    x: 38
                    anchors.verticalCenter: parent.verticalCenter
                    name: "add"
                    size: 20
                    color: Colors.primary
                }
                TextInput {
                    id: adder
                    x: 70
                    width: parent.width - x - 12
                    anchors.verticalCenter: parent.verticalCenter
                    color: Colors.textOnSurface
                    selectionColor: Style.alpha(Colors.primary, 0.4)
                    font.family: Style.font
                    font.pixelSize: Style.textSize("body") + 1
                    clip: true
                    onAccepted: {
                        addWord.keep();
                        const t = text.trim();
                        if (t === "")
                            return;
                        todo.append({ iid: root.newId(), text: t, done: false });
                        text = "";
                        root.save();
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: addWord.value === ""
                        text: "Add an item"
                        color: Style.alpha(Colors.textOnSurfaceVariant, 0.8)
                    }
                }
                Composing {
                    id: addWord
                    field: adder
                }
            }

            // N done ▸
            MouseArea {
                width: parent.width
                height: done.count > 0 ? 36 : 0
                visible: done.count > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showDone = !root.showDone

                Row {
                    x: 36
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron_right"
                        size: 18
                        rotation: root.showDone ? 90 : 0
                        color: Colors.textOnSurfaceVariant
                        Behavior on rotation { NumberAnimation { duration: Motion.fast } }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: done.count + " done"
                        weight: 650
                        color: Colors.textOnSurfaceVariant
                    }
                }
            }

            Column {
                id: doneColumn
                width: parent.width
                visible: root.showDone
                move: Transition {
                    NumberAnimation { properties: "y"; duration: 160; easing.type: Easing.OutCubic }
                }
                Repeater {
                    id: doneRows
                    model: done
                    readonly property bool anyDragging: {
                        count;
                        for (let i = 0; i < count; i++)
                            if (itemAt(i)?.dragging)
                                return true;
                        return false;
                    }
                    ItemRow {
                        list: done
                        rowsColumn: doneColumn
                    }
                }
            }
        }
    }
}
