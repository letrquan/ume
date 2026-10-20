//@ pragma Env MINE_WEATHER_READONLY=1
//@ pragma IconTheme ZorinGrey-Dark
import QtQuick
import QtQuick.Window
import Quickshell
import qs.common
import qs.lock

// The lock screen in a plain window, without locking anything: frames of
// the opening, typing, a wrong password, the power island and unlocking
// are saved as PNGs. Offscreen (nothing on your screen):
//   MINE_LOCK_PREVIEW_OUT=/tmp/lockshots QT_QPA_PLATFORM=offscreen \
//   QSG_RHI_BACKEND=opengl QT_QUICK_BACKEND=rhi qs -p ~/.config/quickshell/mine/lock-preview.qml
// The style and the rest come from Settings (MINE_SETTINGS: another file).
// "While you were away" reads MINE_NOTIF_HISTORY (else the real list, read
// only) for what came in since MINE_LOCK_PREVIEW_SINCE (ms since 1970;
// default: the preview's start).
ShellRoot {
    settings.watchFiles: false

    Window {
        id: win
        width: 1536
        height: 960
        visible: true
        color: "black"

        readonly property string outDir: Quickshell.env("MINE_LOCK_PREVIEW_OUT") || "/tmp"

        LockView {
            id: view
            anchors.fill: parent
            avatar: Quickshell.env("HOME") + "/.face"
            userName: Quickshell.env("USER") ?? "user"
            lockedAt: {
                const since = Number(Quickshell.env("MINE_LOCK_PREVIEW_SINCE"));
                return since > 0 ? new Date(since) : new Date();
            }
        }

        // [time ms, picture name ("" = none), what to do]
        readonly property var steps: [
            [60, "00-open-60", () => {}],
            [200, "00-open-200", () => {}],
            [400, "00-open-400", () => {}],
            [650, "00-open-650", () => {}],
            [1000, "00-open-1000", () => {}],
            // Face unlock (lock.qml's faceState): looking, then not recognized.
            [1050, "", () => { view.faceState = "looking"; }],
            [1400, "01-face-looking", () => {}],
            [1450, "", () => { view.faceState = "failed"; }],
            [1800, "01-face-failed", () => {}],
            [1850, "", () => { view.faceState = "idle"; }],
            [2200, "02-idle", () => {}],
            [2300, "", () => { view.password = "h"; }],
            [2450, "", () => { view.password = "hu"; }],
            [2600, "", () => { view.password = "hun"; }],
            [2750, "", () => { view.password = "hunt"; }],
            [3300, "03-typed", () => {}],
            [3350, "", () => { view.authState = "busy"; }],
            [3600, "04-busy", () => {}],
            [3650, "", () => { view.authState = "failed"; view.password = ""; }],
            [3760, "05-shake", () => {}],
            [4400, "05-failed", () => {}],
            [4450, "", () => { view.authState = "idle"; view.powerOpen = true; }],
            [5200, "06-power", () => {}],
            [5250, "", () => { view.powerOpen = false; }],
            // Left alone (the mac style keeps only the time after
            // Style.lockHideAfter s; set it low in MINE_SETTINGS to see it).
            [7800, "08-rest", () => {}],
            [7850, "", () => { view.password = "x"; }],
            [8300, "09-awake", () => {}],
            [8350, "", () => { view.authState = "success"; }],
            [8500, "10-close-150", () => {}],
            [8750, "10-close-400", () => {}],
            [9100, "10-close-750", () => {}]
        ]
        property int step: 0
        property int elapsed: 0

        Timer {
            interval: 50
            repeat: true
            running: true
            onTriggered: {
                win.elapsed += interval;
                while (win.step < win.steps.length && win.steps[win.step][0] <= win.elapsed) {
                    const s = win.steps[win.step++];
                    s[2]();
                    if (s[1] !== "") {
                        const name = s[1];
                        win.contentItem.grabToImage(r => r.saveToFile(win.outDir + "/" + name + ".png"));
                    }
                }
                if (win.step >= win.steps.length && win.elapsed > 9500)
                    Qt.quit();
            }
        }
    }
}
