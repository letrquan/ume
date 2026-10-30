import QtQuick

// A word an input method is still composing in a text field (fcitx5's
// bamboo holds a Vietnamese word as "preedit" until Space; Qt keeps it out
// of `text`). Tested in mango: when the field's window loses the keyboard
// (a click on another window, the launcher, the panel closing) bamboo
// drops that word, and Qt.inputMethod.commit() doesn't bring it in either
// (text-input-v3). So:
//   value   the text as it looks, the composing word in it: what's saved
//   keep()  puts the word into `text` itself (also done by itself when the
//           window loses the keyboard). Should the input method send the
//           same word right after all, it isn't doubled.
QtObject {
    id: root

    required property Item field            // a TextInput or a TextEdit

    readonly property string value: field.preeditText === "" ? field.text
        : field.text.slice(0, field.cursorPosition) + field.preeditText + field.text.slice(field.cursorPosition)
    readonly property bool windowActive: field.Window.active
    onWindowActiveChanged: if (!windowActive) keep()

    // The last word kept: { text: the text after it, word, at (where it ends) }.
    property var kept: null

    function keep() {
        const word = field.preeditText;
        if (word === "")
            return;
        const at = field.cursorPosition;
        const before = field.text;
        field.text = before.slice(0, at) + word + before.slice(at);
        field.cursorPosition = at + word.length;
        kept = { text: field.text, word: word, at: at + word.length };
        forget.restart();
    }

    property Timer forget: Timer {
        interval: 1500
        onTriggered: root.kept = null
    }
    property Connections late: Connections {
        target: root.field
        function onTextChanged() {
            const k = root.kept;
            if (k && root.field.text === k.text.slice(0, k.at) + k.word + k.text.slice(k.at)) {
                root.kept = null;
                root.field.text = k.text;
                root.field.cursorPosition = k.at;
            }
        }
    }
}
