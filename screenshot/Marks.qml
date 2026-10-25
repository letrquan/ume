import QtQuick

// All the marks of a screenshot markup (screenshot/Mark.qml), in the
// picked rectangle's coordinates: the blurred rectangles first, so the
// lines, arrows, boxes and text always sit on top of them (in the saved
// file too), then the rest in the order they were drawn. `current` is the
// one being drawn right now.
// `marks` is a plain array; a new mark, an undo or a redo only adds or
// removes that one mark here (sync()), so a page of handwriting doesn't
// redraw every stroke each time one more is lifted.
Item {
    id: root

    property var marks: []
    property var current: null
    property var geo: null
    property Item picture: null
    property int block: 16

    property var shown: []              // what the two lists below hold, in order
    onMarksChanged: sync()
    Component.onCompleted: sync()

    function sync() {
        const a = shown, b = marks;
        let same = 0;
        while (same < a.length && same < b.length && a[same] === b[same])
            same++;
        // Each list is in drawing order, so the last ones go from its end.
        for (let i = a.length - 1; i >= same; i--) {
            const list = a[i].kind === "blur" ? blurs : lines;
            list.remove(list.count - 1);
        }
        for (let i = same; i < b.length; i++)
            (b[i].kind === "blur" ? blurs : lines).append({ json: JSON.stringify(b[i]) });
        shown = b.slice();
    }

    ListModel { id: blurs }
    ListModel { id: lines }

    Repeater {
        model: blurs
        Mark {
            required property string json
            mark: JSON.parse(json)
            geo: root.geo
            picture: root.picture
            block: root.block
        }
    }
    Mark {
        mark: root.current?.kind === "blur" ? root.current : null
        geo: root.geo
        picture: root.picture
        block: root.block
    }
    Repeater {
        model: lines
        Mark {
            required property string json
            mark: JSON.parse(json)
            geo: root.geo
            picture: root.picture
            block: root.block
        }
    }
    Mark {
        mark: root.current && root.current.kind !== "blur" ? root.current : null
        geo: root.geo
        picture: root.picture
        block: root.block
    }
}
