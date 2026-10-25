import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import qs.common
import qs.lock

// The login screen (greeter.qml, run by greetd inside cage): the lock's
// mac style (MacView: the time, you, the password, ⏻) plus a session chip
// at the bottom left and a Caps Lock hint.
//
// Logging in: greetd asks PAM, PAM asks for the password, we answer with
// what was typed; once it says yes, the chosen session (a file in
// /usr/share/wayland-sessions) starts and this quits, which ends cage, which
// lets greetd start your session.
//
// Where things are (all readable by the `greeter` user):
//   /var/lib/mine-greeter    the wallpaper, colors, your picture, a few settings
//                            (copied by the shell: scripts/greeter-sync.sh)
//   /var/cache/mine-greeter  the last user and session (written here)
// MINE_GREETER_DRYRUN=1 (the test on VT 7): a right password only shows
// "Password OK (test mode)"; nothing starts and ⏻ does nothing.
// Tests: MINE_GREETER_ASSETS, MINE_GREETER_STATE, MINE_GREETER_SESSIONS,
// MINE_GREETER_PASSWD point at other folders/files; MINE_GREETER_NOPOWER=1.
Item {
    id: root

    readonly property string assetDir: Quickshell.env("MINE_GREETER_ASSETS") || "/var/lib/mine-greeter"
    readonly property string stateDir: Quickshell.env("MINE_GREETER_STATE") || "/var/cache/mine-greeter"
    readonly property string sessionsDir: Quickshell.env("MINE_GREETER_SESSIONS") || "/usr/share/wayland-sessions"
    readonly property string passwdPath: Quickshell.env("MINE_GREETER_PASSWD") || "/etc/passwd"
    readonly property bool dryRun: Quickshell.env("MINE_GREETER_DRYRUN") === "1"
    readonly property bool noPower: dryRun || Quickshell.env("MINE_GREETER_NOPOWER") === "1"
    // For the tests (greeter-setup/test): what's typed, and the chip.
    property alias password: view.password
    property alias chip: chip
    property alias powerOpen: view.powerOpen

    // ---- Who and what ---------------------------------------------------------------------
    // People (uid 1000–59999 with a login shell) and sessions, plus the last
    // ones used.
    property var users: []
    property var sessions: []          // [{ id, name, exec, desktopNames }]
    property string user: ""
    property string sessionId: ""
    readonly property var session: sessions.find(s => s.id === sessionId) ?? sessions[0] ?? null

    FileView {
        id: passwd
        path: root.passwdPath
        blockLoading: true
        printErrors: false
        onLoaded: root.readUsers()
    }
    function readUsers() {
        const list = [];
        for (const line of passwd.text().split("\n")) {
            const f = line.split(":");
            const uid = Number(f[2]);
            const shell = f[6] ?? "";
            if (f.length >= 7 && uid >= 1000 && uid < 60000 && !/(nologin|false)$/.test(shell))
                list.push(f[0]);
        }
        users = list;
        pickDefaults();
    }

    // Each .desktop file: id (the file name), Name, Exec, DesktopNames.
    Process {
        id: sessionReader
        running: true
        command: ["sh", "-c", 'for f in "$1"/*.desktop; do [ -f "$f" ] || continue; '
            + 'awk -v id="$(basename "$f" .desktop)" \''
            + '/^\\[/ { sec = ($0 == "[Desktop Entry]") } '
            + 'sec && /^Name=/ && name == "" { name = substr($0, 6) } '
            + 'sec && /^Exec=/ && exec == "" { exec = substr($0, 6) } '
            + 'sec && /^DesktopNames=/ { dn = substr($0, 14) } '
            + 'sec && /^(Hidden|NoDisplay)=true/ { hide = 1 } '
            + 'END { if (!hide && exec != "") printf "%s\\t%s\\t%s\\t%s\\n", id, name, exec, dn }'
            + '\' "$f"; done', "sh", root.sessionsDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.sessions = this.text.split("\n").filter(l => l !== "").map(l => {
                    const f = l.split("\t");
                    return {
                        id: f[0],
                        name: f[1] || f[0],
                        // %f, %U... mean nothing for a session.
                        exec: (f[2] ?? "").replace(/\s*%[a-zA-Z]/g, "").trim(),
                        desktopNames: f[3] ?? ""
                    };
                }).sort((a, b) => a.name.localeCompare(b.name));
                root.pickDefaults();
            }
        }
    }

    FileView {
        id: stateFile
        path: root.stateDir + "/state.json"
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }
    // The shell's "Switch to GNOME" (scripts/switch-session.sh) leaves
    // { session, at } here. It picks the session once: only while newer
    // than the note the last login saw (noteAt in state.json), since this
    // user can't delete it.
    FileView {
        id: noteFile
        path: root.assetDir + "/next-session.json"
        blockLoading: true
        printErrors: false
    }
    property real noteAt: 0
    property bool picked: false
    function pickDefaults() {
        if (picked || users.length === 0 || sessions.length === 0)
            return;
        picked = true;
        let saved = {}, note = {};
        try {
            saved = JSON.parse(stateFile.text() || "{}");
        } catch (e) {}
        try {
            note = JSON.parse(noteFile.text() || "{}");
        } catch (e) {}
        user = users.includes(saved.user) ? saved.user : users[0];
        noteAt = Number(saved.noteAt) || 0;
        const fresh = Number(note.at) > noteAt && sessions.some(s => s.id === note.session);
        if (fresh)
            noteAt = Number(note.at);
        sessionId = fresh ? note.session
            : sessions.some(s => s.id === saved.session) ? saved.session
            : sessions.some(s => s.id === "mango") ? "mango" : sessions[0].id;
    }
    function remember() {
        stateFile.setText(JSON.stringify({ user: user, session: sessionId, noteAt: noteAt }, null, 1) + "\n");
    }

    // ---- Logging in ---------------------------------------------------------------------
    property string authState: "idle"      // idle | busy | failed | success
    property string authMessage: ""
    // The typed password, kept only until PAM asks for it.
    property string pending: ""
    // PAM asked a second question (a new password, a code): the next Enter
    // answers it.
    property bool awaitingAnswer: false

    function submit() {
        const typed = view.password;
        if (authState === "busy" || authState === "success" || typed === "")
            return;
        if (!Greetd.available) {
            authState = "failed";
            authMessage = "greetd isn't running";
            return;
        }
        authState = "busy";
        authMessage = "";
        if (awaitingAnswer) {
            awaitingAnswer = false;
            view.password = "";
            Greetd.respond(typed);
            return;
        }
        pending = typed;
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        Greetd.createSession(user);
    }

    // greetd should answer within moments (PAM's delay after a wrong
    // password is ~2 s); if it doesn't, say so instead of spinning forever.
    Timer {
        running: root.authState === "busy"
        interval: 10000
        onTriggered: {
            root.pending = "";
            root.awaitingAnswer = false;
            if (Greetd.state !== GreetdState.Inactive)
                Greetd.cancelSession();
            view.password = "";
            root.authMessage = "No answer from greetd, try again";
            root.authState = "failed";
            console.warn("greeter: greetd didn't answer in 10 s");
        }
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (!responseRequired) {
                // Information or a warning from PAM: show it, carry on.
                if (message !== "")
                    root.authMessage = message;
                Greetd.respond("");
            } else if (root.pending !== "") {
                // The password question: answer with what was typed.
                const answer = root.pending;
                root.pending = "";
                Greetd.respond(answer);
            } else {
                // Another question: show it and wait for the next Enter.
                root.authState = "idle";
                root.authMessage = message;
                root.awaitingAnswer = true;
                view.password = "";
            }
        }
        function onAuthFailure(message) {
            root.pending = "";
            root.awaitingAnswer = false;
            view.password = "";
            root.authMessage = "";          // MacView then says "Wrong password"
            root.authState = "failed";
            console.log("greeter: login failed for", root.user, message !== "" ? "(" + message + ")" : "");
        }
        function onReadyToLaunch() {
            root.pending = "";
            root.remember();
            if (root.dryRun) {
                Greetd.cancelSession();
                root.authState = "idle";
                root.authMessage = "Password OK (test mode)";
                view.password = "";
                console.log("greeter (dry run): would start", JSON.stringify(root.launchCommand()));
                return;
            }
            root.authState = "success";     // MacView's unlock: fade and grow
            logIn.restart();                // then dim to dark, then the session
        }
        function onError(error) {
            root.pending = "";
            root.awaitingAnswer = false;
            root.authState = "failed";
            root.authMessage = error;
            console.warn("greeter:", error);
        }
    }

    // The session, with the variables a display manager sets. greetd JOINS
    // the parts with spaces and runs `exec <that>` through /bin/sh -c, so
    // they must already be shell text: the desktop file's Exec goes in as
    // it is (a separate "sh", "-c", "exec mango" would become
    // `sh -c exec mango`, an empty session). What the session prints goes
    // to the journal (journalctl -b -t <session>-session), like GDM's;
    // greetd itself throws it away.
    function launchCommand() {
        const s = session;
        if (!s)
            return { cmd: [], env: [] };
        const names = s.desktopNames.split(";").filter(n => n !== "");
        return {
            cmd: ["systemd-cat", "--identifier=" + s.id + "-session", "--", s.exec],
            env: [
                "XDG_SESSION_TYPE=wayland",
                "XDG_SESSION_DESKTOP=" + s.id,
                "XDG_CURRENT_DESKTOP=" + (names.length > 0 ? names.join(":") : s.id)
            ]
        };
    }
    function launch() {
        const l = root.launchCommand();
        console.log("greeter: starting", root.session?.name, "for", root.user);
        Greetd.launch(l.cmd, l.env, true);
    }
    // Logging in, one fade through dark: the UI fades and grows (MacView,
    // 480 ms), meanwhile the picture dims to the theme's dark surface, the
    // very color mango shows (root_color) until the desktop's wallpaper
    // fades in (services/Intro.qml). Then the session starts, ~780 ms after
    // Enter. No bright picture → black cut.
    SequentialAnimation {
        id: logIn
        PauseAnimation { duration: 260 }
        NumberAnimation {
            target: dim; property: "opacity"; to: 1; duration: 440
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects
        }
        PauseAnimation { duration: 80 }    // a frame or two of plain dark
        ScriptAction { script: root.launch() }
    }

    // ---- Caps Lock -----------------------------------------------------------------------
    property string capsPath: ""
    property bool capsOn: false
    Process {
        running: true
        command: ["sh", "-c", "ls -d /sys/class/leds/*capslock* 2>/dev/null | head -n 1"]
        stdout: StdioCollector {
            onStreamFinished: root.capsPath = this.text.trim()
        }
    }
    FileView {
        id: capsFile
        path: root.capsPath !== "" ? root.capsPath + "/brightness" : ""
        printErrors: false
        onLoaded: root.capsOn = parseInt(text()) > 0
    }
    Timer {
        running: root.capsPath !== "" && root.authState !== "success"
        interval: 400
        repeat: true
        onTriggered: capsFile.reload()
    }

    // ---- What you see --------------------------------------------------------------------
    MacView {
        id: view
        anchors.fill: parent
        userName: root.user
        // Copied by greeter-sync.sh from ~/.face; without one, your initial.
        avatar: root.user !== "" ? root.assetDir + "/face-" + root.user : ""
        authState: root.authState
        // A wrong password with Caps Lock on says both.
        authMessage: root.authMessage !== "" ? root.authMessage
            : !root.capsOn ? ""
            : root.authState === "failed" ? "Wrong password · Caps Lock is on" : "Caps Lock is on"

        // Typing again after a wrong password (or the test-mode note) clears it.
        onPasswordChanged: {
            if (password === "")
                return;
            if (root.authState === "failed")
                root.authState = "idle";
            if (!root.awaitingAnswer)
                root.authMessage = "";
        }
        onSubmit: root.submit()
        onPower: name => {
            if (root.noPower) {
                root.authMessage = "Would " + (name === "poweroff" ? "shut down" : name) + " (test mode)";
                console.log("greeter (dry run): would run systemctl", name);
                return;
            }
            Quickshell.execDetached(["systemctl", name]);
        }
    }

    // Bottom left: which session starts (click for the others), and with
    // more than one person, who logs in.
    SessionChip {
        id: chip
        x: 22
        y: root.height - height - 16
        sessions: root.sessions
        current: root.session
        users: root.users
        user: root.user
        boost: view.light.chip
        enabled: root.authState !== "busy" && root.authState !== "success"
        opacity: root.authState === "success" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 300 } }
        onPicked: id => {
            root.sessionId = id;
            view.focusField();
        }
        onUserPicked: name => {
            root.user = name;
            view.password = "";
            view.focusField();
        }
    }

    // See logIn: covers everything at the end.
    Rectangle {
        id: dim
        anchors.fill: parent
        color: Colors.surface
        opacity: 0
        visible: opacity > 0
    }

    // At boot it comes after the boot logo's black screen: out of black,
    // once the wallpaper is on screen (at most 1.5 s), instead of popping in.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: view.pictureReady || fadeInAnyway.fired ? 0 : 1
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
        }
    }
    Timer {
        id: fadeInAnyway
        property bool fired: false
        interval: 1500
        running: true
        onTriggered: fired = true
    }
}
