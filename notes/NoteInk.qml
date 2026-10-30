import QtQuick
import qs.common
import qs.services
import qs.ink

// A drawing page in the notes panel: write or sketch with the pen (its
// pressure), the mouse, or (Style.inkTouch) a finger, on a sheet of paper:
// the screen's ink (ink/InkCanvas.qml) with pen, highlighter, eraser, five
// inks, three sizes, undo / redo and clear. Every stroke is saved as its
// points (Notes.update: strokes, and the page's size for the desktop card).
Item {
    id: root

    required property string noteId
    property string tool: "pen"
    property int colorIndex: 0
    property int sizeIndex: 0
    readonly property var colors: ["#1c1c1e", "#0a84ff", "#ff453a", "#30d158", "#ffd60a"]
    readonly property var widths: [2.5, 4, 7]

    Component.onCompleted: {
        const n = Notes.find(noteId);
        title.text = n?.title ?? "";
        canvas.load(n?.strokes ?? []);
    }
    function save() {
        if (Notes.find(noteId))
            Notes.update(noteId, { strokes: canvas.saved(), w: paper.width, h: paper.height });
    }
    Connections {
        target: Notes
        function onClosing() {
            titleWord.keep();
        }
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

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: titleWord.value === ""
            text: "Drawing"
            role: "headline"
            color: Style.alpha(Colors.textOnSurfaceVariant, 0.7)
        }
    }
    Composing {
        id: titleWord
        field: title
        onValueChanged: Notes.update(root.noteId, { title: value })
    }

    // ---- Tools -----------------------------------------------------------------------
    component ToolButton: MouseArea {
        id: button
        property string icon: ""
        property bool chosen: false
        property bool on: true
        width: 34
        height: 34
        enabled: on
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: button.chosen ? Colors.primary : Colors.textOnSurface
            opacity: button.chosen ? 1 : button.containsMouse ? Style.hoverTint : 0
        }
        Icon {
            anchors.centerIn: parent
            name: button.icon
            size: 19
            fill: button.chosen ? 1 : 0
            color: button.chosen ? Colors.textOnPrimary : Colors.textOnSurface
            opacity: button.on ? 1 : 0.35
        }
    }

    Row {
        id: tools
        y: title.height + 4
        x: 2
        height: 36
        spacing: 1

        ToolButton { icon: "stylus"; chosen: root.tool === "pen"; onClicked: root.tool = "pen" }
        ToolButton { icon: "ink_highlighter"; chosen: root.tool === "highlighter"; onClicked: root.tool = "highlighter" }
        ToolButton { icon: "ink_eraser"; chosen: root.tool === "eraser"; onClicked: root.tool = "eraser" }
        Item { width: 6; height: 1 }
        Repeater {
            model: root.colors.length
            MouseArea {
                id: swatch
                required property int index
                width: 26
                height: 34
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.colorIndex = index;
                    if (root.tool === "eraser")
                        root.tool = "pen";
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: root.colorIndex === swatch.index ? 20 : 16
                    height: width
                    radius: width / 2
                    color: root.colors[swatch.index]
                    border.width: root.colorIndex === swatch.index ? 2 : 1
                    border.color: root.colorIndex === swatch.index ? Colors.textOnSurface : Style.alpha(Colors.textOnSurface, 0.3)
                }
            }
        }
        MouseArea {
            width: 32
            height: 34
            cursorShape: Qt.PointingHandCursor
            onClicked: root.sizeIndex = (root.sizeIndex + 1) % root.widths.length
            Rectangle {
                anchors.centerIn: parent
                width: [5, 8, 13][root.sizeIndex]
                height: width
                radius: width / 2
                color: Colors.textOnSurface
            }
        }
        Item { width: 4; height: 1 }
        ToolButton { icon: "undo"; on: canvas.canUndo; onClicked: canvas.undo() }
        ToolButton { icon: "redo"; on: canvas.canRedo; onClicked: canvas.redo() }
        ToolButton { icon: "delete_sweep"; on: canvas.hasInk; onClicked: canvas.clear() }
    }

    // ---- The paper ---------------------------------------------------------------------
    Rectangle {
        id: paper
        y: tools.y + tools.height + 6
        width: parent.width
        height: parent.height - y
        radius: 16
        color: "#fbfaf5"
        clip: true

        // Faint lines, like a notepad.
        Repeater {
            model: Math.floor(paper.height / 32)
            Rectangle {
                required property int index
                x: 14
                y: 32 * (index + 1)
                width: paper.width - 28
                height: 1
                color: Qt.rgba(0.2, 0.35, 0.6, 0.12)
            }
        }

        InkCanvas {
            id: canvas
            anchors.fill: parent
            tool: root.tool
            color: root.colors[root.colorIndex]
            lineWidth: root.widths[root.sizeIndex]
            touchDraws: Style.inkTouch
            onEdited: root.save()
        }
    }
}
