//@ pragma Env QT_QPA_PLATFORMTHEME=none
//@ pragma Env QT_QPA_PLATFORMTHEME_QT6=none
//@ pragma Env MINE_WEATHER_READONLY=1
//@ pragma IconTheme ZorinGrey-Dark
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.common
import qs.lock
import "common/sounds.js" as SoundFiles

// The lock screen. A second way into this shell (shell.qml never loads
// lock/), so it has the same colors, glass, fonts and settings
// (Settings → Lock screen) as the bar. It locks the session as soon as it
// starts and quits after a successful unlock, so it uses no memory while
// you're not locked.
//
// Start it with ~/.local/bin/qs-lock (`qs -n -d -p <this file>`); never
// from a terminal you need: the screen locks right away.
// The look: lock/LockView.qml. To see it without locking: lock-preview.qml.
ShellRoot {
    id: shell

    // A running lock never reloads itself (e.g. while the shell is updated).
    settings.watchFiles: false

    property string password: ""
    property string authState: "idle"     // idle | busy | failed | success
    property string authMessage: ""
    readonly property string marker: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-lock.secure"
    readonly property date lockedAt: new Date()

    // ---- The password ------------------------------------------------------------------
    function submit() {
        if (authState === "busy" || authState === "success" || password.length === 0)
            return;
        authState = "busy";
        authMessage = "";
        if (!pam.start()) {
            authState = "failed";
            authMessage = "Could not start authentication";
        }
    }

    function unlock() {
        if (authState === "success")
            return;
        authState = "success";      // LockView plays the unlock animation
        if (face.active)
            face.abort();
        unlockTimer.start();
        playSound("unlock");
    }

    // ---- Your face ----------------------------------------------------------------------
    // Howdy and the IR camera, beside the password (Settings → Lock screen →
    // Unlock with your face). Its own PAM conversation on /etc/pam.d/mine-face
    // (pam_howdy then pam_deny, set up by setup/face-setup.sh); the password
    // one above stays on "login" and is never touched, so a missing camera or
    // a broken face setup can't stop you typing your password. It doesn't
    // look the moment the lock is up (you may be getting up to leave, still
    // in front of the camera): the first look waits for you to type or move
    // the mouse on the lock (faceWake). After that, only when you come back
    // to a resting lock or click your picture; never in a loop. A failed look
    // doesn't count as a wrong password (no faillock in that file).
    property string faceState: "off"      // off | idle | looking | failed
    property bool faceReady: false        // that PAM file and your face model are there
    property real faceStartedAt: 0

    function faceTry() {
        if (!faceReady || !Style.lockFace || face.active || !lock.secure
            || authState === "busy" || authState === "success")
            return;
        faceStartedAt = Date.now();
        faceState = "looking";
        if (!face.start())
            faceState = "failed";
    }

    // You're there (a key or a mouse move on the lock): the first look, not
    // within 2 s of locking (hands still leaving the keyboard), and not again
    // by itself after "not recognized".
    function faceWake() {
        if (faceState === "idle" && Date.now() - lockedAt.getTime() > 2000)
            faceTry();
    }

    Process {
        running: true
        command: ["sh", "-c", "test -r /etc/pam.d/mine-face && test -r \"/etc/howdy/models/$USER.dat\""]
        onExited: code => {
            shell.faceReady = code === 0;
            shell.faceState = shell.faceReady && Style.lockFace ? "idle" : "off";
        }
    }

    PamContext {
        id: face
        configDirectory: "/etc/pam.d"
        config: "mine-face"

        // pam_howdy asks nothing; its notes ("Failure, timeout reached") aren't shown.
        onPamMessage: {
            if (this.responseRequired)
                this.respond("");
        }
        onCompleted: result => {
            if (result === PamResult.Success) {
                shell.unlock();
                return;
            }
            if (shell.faceState !== "looking")
                return;
            // An answer within a moment means it didn't look at all (the lid
            // is shut, e.g. docked): stay quiet instead of "not recognized".
            shell.faceState = Date.now() - shell.faceStartedAt < 800 ? "idle" : "failed";
        }
        onError: error => {
            if (shell.faceState === "looking")
                shell.faceState = "failed";
        }
    }

    // Locking / unlocking sounds (Settings → Sounds; the files:
    // common/sounds.js). Detached, so the unlock one outlives the lock.
    function playSound(name) {
        if (!Style.soundLock || Style.soundVolume <= 0)
            return;
        const cmd = SoundFiles.command(name, Style.soundVolume);
        if (Quickshell.env("MINE_SOUNDS_DRYRUN") === "1")
            console.log("sounds (dry run):", name, JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    PamContext {
        id: pam
        configDirectory: "/etc/pam.d"
        config: "login"

        onPamMessage: {
            if (this.responseRequired)
                this.respond(shell.password);
            else if (this.messageIsError)
                shell.authMessage = this.message;
        }
        onCompleted: result => {
            if (result === PamResult.Success) {
                shell.unlock();
            } else {
                shell.password = "";
                shell.authState = "failed";
                if (result === PamResult.MaxTries)
                    shell.authMessage = "Too many tries, wait a moment";
                resetTimer.restart();
            }
        }
        onError: error => {
            shell.password = "";
            shell.authState = "failed";
            shell.authMessage = "Authentication error";
            resetTimer.restart();
        }
    }

    // After a wrong password, back to normal once the shake has played.
    Timer {
        id: resetTimer
        interval: 2200
        onTriggered: if (shell.authState === "failed") shell.authState = "idle"
    }

    // Let the unlock animation play, then let go of the lock and quit.
    Timer {
        id: unlockTimer
        interval: 700      // LockView's closing animation (~650 ms)
        onTriggered: {
            Quickshell.execDetached(["rm", "-f", shell.marker]);
            lock.locked = false;
            Qt.quit();
        }
    }

    // Tells qs-lock that the compositor has confirmed the lock.
    Process {
        id: markSecure
        command: ["touch", shell.marker]
    }

    WlSessionLock {
        id: lock
        locked: true
        onSecureChanged: {
            if (secure) {
                markSecure.running = true;
                shell.playSound("lock");
            }
        }

        WlSessionLockSurface {
            color: Colors.surface

            LockView {
                id: view
                anchors.fill: parent
                userName: Quickshell.env("USER") ?? "user"
                avatar: Quickshell.env("HOME") + "/.face"
                lockedAt: shell.lockedAt
                authState: shell.authState
                authMessage: shell.authMessage
                faceState: shell.faceState
                onFaceTry: shell.faceTry()
                onWoke: shell.faceWake()

                // One password shared by every screen (copied both ways by
                // hand: LockView hands it on to the style that's showing).
                Component.onCompleted: password = shell.password
                Connections {
                    target: shell
                    function onPasswordChanged() {
                        if (view.password !== shell.password)
                            view.password = shell.password;
                    }
                }
                onPasswordChanged: {
                    if (password !== shell.password) {
                        shell.password = password;
                        if (shell.authState === "failed")
                            shell.authState = "idle";
                        shell.authMessage = "";
                    }
                }

                onSubmit: shell.submit()
                onPower: name => {
                    if (name === "suspend")
                        Quickshell.execDetached(["systemctl", "suspend"]);
                    else if (name === "reboot")
                        Quickshell.execDetached(["systemctl", "reboot"]);
                    else if (name === "poweroff")
                        Quickshell.execDetached(["systemctl", "poweroff"]);
                }
            }
        }
    }
}
