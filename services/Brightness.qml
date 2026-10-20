pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Screen brightness (0-1) of the laptop panel.
// The kernel announces every backlight change through udev, so we listen to
// `udevadm monitor` and re-read the value only when something changed,
// whoever changed it (keys, Noctalia's slider, brightnessctl...).
Singleton {
    id: root

    property string device: ""          // e.g. amdgpu_bl1
    property int max: 0
    property int raw: -1
    readonly property bool ready: max > 0 && raw >= 0
    readonly property real value: ready ? raw / max : 0

    // Set brightness (0-1). Not used by keys yet: they still go to Noctalia.
    function set(fraction: real) {
        const percent = Math.round(Math.max(0.01, Math.min(1, fraction)) * 100);
        Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", percent + "%"]);
    }

    // Which backlight, and its maximum. Prints e.g.
    // amdgpu_bl1,backlight,300000,100%,300000
    Process {
        running: true
        command: ["brightnessctl", "-m", "-c", "backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split("\n")[0].split(",");
                if (fields.length < 5)
                    return;
                // max first: setting the device starts reading the value.
                root.max = parseInt(fields[4]);
                root.device = fields[0];
            }
        }
    }

    FileView {
        id: file
        path: root.device !== "" ? "/sys/class/backlight/" + root.device + "/brightness" : ""
        onLoaded: {
            const v = parseInt(text());
            if (!isNaN(v))
                root.raw = v;
        }
    }

    Process {
        id: monitor
        running: root.device !== ""
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=backlight"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes(" change "))
                    file.reload();
            }
        }
        onExited: restart.start()
    }

    Timer {
        id: restart
        interval: 2000
        onTriggered: monitor.running = true
    }
}
