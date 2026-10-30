import QtQuick
import Quickshell
import Quickshell.Io

// One JSON state file of the shell's own (the notes, the timers), kept the
// safe way. (Not services/StateFile.qml: this one reads at once, and saves
// a moment later, or on flush(), through scripts/state-save.sh.) Saving goes through scripts/state-save.sh: a new private file
// next to it, moved over the old one, so a reader never sees half a file
// and a link someone left at its name is replaced, never written through
// (FileView's atomicWrites would follow the link: Qt's QSaveFile writes to
// a link's target, which could be any file of yours).
// Reading is FileView's, at once (blockLoading), so nothing done in the
// first moments is read over afterwards. (Whoever could leave a link there
// could write the file itself, so reading through one shows nothing new.)
//
// load() reads it: loaded(text), "" when it's missing or empty. save(text)
// writes it a moment later (a burst of changes is written once, the last
// one); flush() writes what's waiting now. A shell stopped within `delay`
// ms of a change loses that change (on Qt.quit() Quickshell ran neither
// Component.onDestruction nor aboutToQuit here; `qs kill` and a live
// reload weren't tried).
Scope {
    id: root

    required property string path
    property int delay: 400                 // ms after the last save()

    property bool ready: false              // load() has answered
    readonly property bool dirty: waiting !== null
    property var waiting: null              // the text still to write, or null

    signal loaded(string text)
    signal saved(bool ok)

    function load() {
        // Setting the path reads it right here (blockLoading); reload()
        // would read it later. A missing file reads as "".
        reader.path = "";
        reader.path = root.path;
        ready = true;
        loaded(reader.text());
    }

    function save(text) {
        waiting = text;
        later.restart();
    }

    function flush() {
        later.stop();
        if (waiting === null)
            return;
        if (writer.running) {
            writer.again = true;
            return;
        }
        writer.text = waiting;
        waiting = null;
        writer.stdinEnabled = true;
        writer.running = true;
    }

    Timer {
        id: later
        interval: root.delay
        onTriggered: root.flush()
    }

    FileView {
        id: reader
        blockLoading: true
        printErrors: false
    }

    Process {
        id: writer
        property string text: ""
        property bool again: false
        command: ["sh", Quickshell.shellDir + "/scripts/state-save.sh", root.path]
        onStarted: {
            write(text);
            text = "";
            stdinEnabled = false;
        }
        onExited: code => {
            if (code !== 0)
                console.warn("state: saving", root.path, "failed", code);
            root.saved(code === 0);
            if (again) {
                again = false;
                root.flush();
            }
        }
    }
}
