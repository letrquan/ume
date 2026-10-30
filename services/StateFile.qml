import QtQuick
import Quickshell
import Quickshell.Io

// A small state file of ours, read and written so that nothing planted at
// its name can redirect it (screen time, AI usage):
//  - load(): reads it once. A link at that name is not followed (refused():
//    the next save puts a real file there instead), nor is anything else
//    that isn't a plain file. loaded("") when there's no file yet.
//  - save(text): written to a new private file in the same folder (mktemp
//    makes a fresh name, so it never writes through something already
//    there) and then moved over the old one: the move is atomic, and it
//    replaces a link at the name instead of writing through it. The text
//    goes on stdin, never in a command line. One save at a time; the
//    newest text waiting goes next.
// A save still running when the shell is killed is lost (the old file
// stays as it was), so callers save often enough not to mind.
Scope {
    id: root

    required property string path

    signal loaded(string text)
    signal refused(string why)
    signal saved(bool ok)

    readonly property bool busy: writer.running || reader.running

    function load() {
        if (path === "" || reader.running)
            return;
        reader.running = true;
    }

    // Waiting to go once the save before it is done.
    property var waiting: null
    function save(text) {
        if (path === "")
            return;
        if (writer.running) {
            waiting = text;
            return;
        }
        writer.input = text;
        writer.stdinEnabled = true;
        writer.running = true;
    }

    // Exits 3 for a link, 4 for no file, 5 for something else than a file.
    Process {
        id: reader
        command: ["sh", "-c", 'f=$1; [ -L "$f" ] && exit 3; [ -e "$f" ] || exit 4; [ -f "$f" ] || exit 5; exec head -c 4000000 -- "$f"',
                  "sh", root.path]
        property int code: -1
        property int pending: 0
        onRunningChanged: if (running) {
            code = -1;
            pending = 2;
        }
        stdout: StdioCollector {
            id: readOut
            onStreamFinished: reader.settle()
        }
        onExited: exitCode => {
            code = exitCode;
            settle();
        }
        function settle() {
            if (pending <= 0 || --pending > 0)
                return;
            if (code === 0)
                root.loaded(readOut.text);
            else if (code === 4)
                root.loaded("");
            else
                root.refused(code === 3 ? "a link" : code === 5 ? "not a plain file" : "unreadable");
        }
    }

    Process {
        id: writer
        property string input: ""
        command: ["sh", "-c", 'umask 077; f=$1; d=$(dirname -- "$f"); mkdir -p -- "$d" || exit 1; '
                  + 't=$(mktemp -- "$d/.${f##*/}.XXXXXX") || exit 1; '
                  + 'if cat > "$t" && mv -fT -- "$t" "$f"; then exit 0; fi; rm -f -- "$t"; exit 1',
                  "sh", root.path]
        onStarted: {
            write(input);
            input = "";
            stdinEnabled = false;
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("state file:", root.path + ":", text.trim().split("\n").pop())
        }
        onExited: exitCode => {
            root.saved(exitCode === 0);
            if (root.waiting !== null) {
                const next = root.waiting;
                root.waiting = null;
                Qt.callLater(() => root.save(next));
            }
        }
    }
}
