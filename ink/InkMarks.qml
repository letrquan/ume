import QtQuick

// All the strokes of an ink canvas (ink/InkStroke.qml each), in drawing
// order, and `current`, the one being drawn. `strokes` is a plain array; a
// change only adds or removes the strokes that changed here (by their id),
// so a page of handwriting isn't drawn again for every new line, an erased
// one or one that faded.
Item {
    id: root

    property var strokes: []
    property var current: null
    property real fadeAfter: 0

    property var shown: []              // the ids the list below holds, in order
    onStrokesChanged: sync()
    Component.onCompleted: sync()

    function sync() {
        const want = strokes ?? [];
        const keep = new Set(want.map(s => s.id));
        // Gone ones first (from the end, so the indexes hold).
        for (let i = shown.length - 1; i >= 0; i--) {
            if (!keep.has(shown[i])) {
                list.remove(i);
                shown.splice(i, 1);
            }
        }
        // Then the new ones, each in its place.
        const have = new Set(shown);
        for (let i = 0; i < want.length; i++) {
            if (have.has(want[i].id))
                continue;
            list.insert(i, { json: JSON.stringify(want[i]) });
            shown.splice(i, 0, want[i].id);
        }
    }

    ListModel { id: list }

    Repeater {
        model: list
        InkStroke {
            required property string json
            stroke: JSON.parse(json)
            fadeAfter: root.fadeAfter
        }
    }
    InkStroke {
        stroke: root.current
    }
}
