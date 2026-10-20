pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The on-screen keyboard (osk/): whether it shows, its page, the keys
// waiting for the next one (⇧, ctrl, alt, super), and the typing.
//
// Typing: wtype (the virtual keyboard protocol, as the clipboard's paste),
// into the focused window. One wtype at a time, so keys never overtake each
// other; keys touched while one runs go together in the next. That's one
// short process per key (12-17 ms each in a test; MINE_OSK_DEBUG=1 logs
// every run with its time).
//
// Tablet mode (services/TabletMode.qml): up when the screen folds back into
// a tablet, away when it folds again. mango runs `mine osk fold` / `mine osk
// unfold` when a switch turns on / off (switchbind); `mine` drops a fold
// with the lid shut, notes the answer in $XDG_RUNTIME_DIR/mine-tablet and
// calls fold() / unfold() here. That file is also read 3 s after start (a
// login or restart folded) and for `mine osk tablet`.
Singleton {
    id: root

    property bool open: false
    // The window exists (open, or sliding away).
    property bool mapped: false
    property string page: "letters"    // "letters" | "symbols"
    property string shift: "off"       // "off" | "once" (the next key) | "caps"
    // Held for the next key only (tap again to let go).
    property bool ctrl: false
    property bool alt: false
    property bool superKey: false

    readonly property bool debug: Quickshell.env("MINE_OSK_DEBUG") === "1"

    function show() {
        unmap.stop();
        if (!open) {
            page = "letters";
            shift = "off";
            ctrl = alt = superKey = false;
        }
        open = true;
        mapped = true;
    }

    function hide() {
        if (!open)
            return;
        open = false;
        unmap.restart();
    }

    function toggle() {
        if (open)
            hide();
        else
            show();
    }

    // The window goes once it has slid away.
    Timer {
        id: unmap
        interval: Motion.normal + 150
        onTriggered: root.mapped = false
    }

    // ---- Keys ------------------------------------------------------------------

    // xkb names for wtype -k: a character typed with ctrl / alt / super held,
    // and the named keys. Letters and digits are their own names.
    readonly property var keysyms: ({
        " ": "space", "!": "exclam", "\"": "quotedbl", "#": "numbersign", "$": "dollar", "%": "percent",
        "&": "ampersand", "'": "apostrophe", "(": "parenleft", ")": "parenright", "*": "asterisk",
        "+": "plus", ",": "comma", "-": "minus", ".": "period", "/": "slash", ":": "colon",
        ";": "semicolon", "<": "less", "=": "equal", ">": "greater", "?": "question", "@": "at",
        "[": "bracketleft", "\\": "backslash", "]": "bracketright", "^": "asciicircum",
        "_": "underscore", "`": "grave", "{": "braceleft", "|": "bar", "}": "braceright", "~": "asciitilde"
    })
    readonly property var named: ({
        back: "BackSpace", enter: "Return", tab: "Tab", esc: "Escape",
        left: "Left", right: "Right", up: "Up", down: "Down"
    })

    property double shiftAt: 0

    // A key of osk/layouts.js was touched. Returns what it typed (so a held
    // ⌫ or arrow can send the same again), or null.
    function tap(key) {
        switch (key.t) {
        case "shift":
            // Once: the next key. Twice quickly: caps lock. Again: off.
            if (shift === "off") {
                shift = "once";
                shiftAt = Date.now();
            } else {
                shift = shift === "once" && Date.now() - shiftAt < 400 ? "caps" : "off";
            }
            return null;
        case "ctrl":
            ctrl = !ctrl;
            return null;
        case "alt":
            alt = !alt;
            return null;
        case "super":
            superKey = !superKey;
            return null;
        case "page":
            page = page === "letters" ? "symbols" : "letters";
            shift = "off";
            return null;
        case "hide":
            hide();
            return null;
        }

        const mods = [];
        if (ctrl)
            mods.push("ctrl");
        if (alt)
            mods.push("alt");
        if (superKey)
            mods.push("logo");
        let part;
        if (key.t) {
            // A named key. ⇧ tapped once goes with it (⇧+arrows select,
            // ⇧+Tab goes back); caps lock doesn't.
            if (shift === "once")
                mods.push("shift");
            part = { args: wrap(mods, ["-k", named[key.t]]) };
        } else {
            const c = shift === "off" ? key.c : key.s;
            if (mods.length === 0) {
                // Plain text. "-" can't be: wtype would take it as an option.
                part = c === "-" ? { args: ["-k", "minus"] } : { text: c };
            } else {
                // With ctrl / alt / super: the key itself, and ⇧ for a capital
                // (ctrl+⇧+c copies in a terminal). Caps lock doesn't count,
                // as on a real keyboard (ctrl+c stays ctrl+c).
                const base = shift === "caps" ? key.c : c;
                const lower = base.toLowerCase();
                if (lower !== base)
                    mods.push("shift");
                part = { args: wrap(mods, ["-k", /^[a-z0-9]$/.test(lower) ? lower : (keysyms[lower] ?? "U" + lower.codePointAt(0).toString(16))]) };
            }
        }
        send(part);
        // They last one key.
        ctrl = alt = superKey = false;
        if (shift === "once")
            shift = "off";
        return part;
    }

    // A held ⌫ or arrow: the same again, unless the last one is still
    // waiting (so it never runs ahead of what you see).
    function again(part) {
        if (part && queue.length === 0)
            send(part);
    }

    // -M ctrl -M shift <key> -m shift -m ctrl
    function wrap(mods, args) {
        const out = [];
        for (const m of mods)
            out.push("-M", m);
        for (const a of args)
            out.push(a);
        for (const m of mods.slice().reverse())
            out.push("-m", m);
        return out;
    }

    // ---- Typing (wtype) ----------------------------------------------------------

    // Waiting for the next wtype: [{ text } | { args }].
    property var queue: []
    readonly property bool typing: typer.running || queue.length > 0
    property double startedAt: 0
    property bool warned: false

    function send(part) {
        queue = queue.concat([part]);
        if (!typer.running)
            flush();
    }

    function flush() {
        if (queue.length === 0 || typer.running)
            return;
        // Text next to text must be one argument: wtype puts a space
        // between two (and a text never starts with "-", see tap()).
        const args = ["wtype"];
        let text = "";
        for (const part of queue) {
            if (part.text !== undefined) {
                text += part.text;
                continue;
            }
            if (text !== "")
                args.push(text);
            text = "";
            for (const a of part.args)
                args.push(a);
        }
        if (text !== "")
            args.push(text);
        queue = [];
        startedAt = Date.now();
        typer.command = args;
        typer.running = true;
    }

    Process {
        id: typer
        onExited: (code, status) => {
            if (root.debug)
                console.log("osk: wtype", JSON.stringify(typer.command.slice(1)), "exit", code, "in", Date.now() - root.startedAt, "ms");
            if (code !== 0 && !root.warned) {
                root.warned = true;
                console.warn("osk: wtype failed (exit " + code + "); is wtype installed?");
            }
            Qt.callLater(root.flush);
        }
    }

    // ---- Tablet mode -------------------------------------------------------------

    // 1 tablet, 0 laptop (TabletMode keeps it, whatever oskAutoTablet says:
    // turning the screen goes by it too).
    readonly property int tabletState: TabletMode.state

    // `mine osk fold` / `mine osk unfold` (mango, when a switch flips on /
    // off: the tablet switches, or the lid; `mine` already left out a fold
    // with the lid shut).
    function fold() {
        TabletMode.fold();
        if (Style.oskAutoTablet)
            show();
    }
    function unfold() {
        TabletMode.unfold();
        if (Style.oskAutoTablet)
            hide();
    }

    // `mine osk tablet`: as the file says now.
    function tablet() {
        TabletMode.reread();
    }

    Connections {
        target: TabletMode
        function onFileRead(state, asked) {
            if (!Style.oskAutoTablet)
                return;
            if (state === 1)
                root.show();
            else if (asked)
                root.hide();
        }
    }
}
