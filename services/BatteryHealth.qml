pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.common

// The laptop battery's health and its charge over the last hours, for the
// battery popup (control/BatteryPopup.qml, a click on the bar's battery).
//  - Health: the kernel's own numbers in /sys/class/power_supply/<BAT>/uevent
//    (one file, read when the popup opens): how much it holds when full now
//    against when it was new (energy_full / energy_full_design, in µWh; or
//    charge_full / charge_full_design in µAh, turned into Wh with
//    voltage_min_design when the battery reports that), the wear (what's
//    lost, 0 when "full" is still above "design", as here: 59.17 / 59.16 Wh),
//    and the charge cycles when the battery counts them (0 = it doesn't).
//  - The graph: UPower's own history (it records the charge each time it
//    changes). Its files in /var/lib/upower are root's (mode 0640), so it's
//    asked over D-Bus instead: GetHistory("charge", seconds, points) on the
//    battery's UPower object, through `busctl --json=short` (points
//    [time, percent, state], newest first). Only while the popup is open,
//    again every minute.
//
// Tests: MINE_BATTERY_SYSFS (a folder instead of /sys/class/power_supply),
// MINE_BATTERY_HEALTH_FAKE = JSON for the UPower side instead of the real
// device ({ nativePath, percent, state ("charging" | "discharging" |
// "full" | "pending"), seconds, rate }).
Singleton {
    id: root

    readonly property string sysfs: Quickshell.env("MINE_BATTERY_SYSFS") || "/sys/class/power_supply"
    readonly property var fake: {
        try {
            const f = Quickshell.env("MINE_BATTERY_HEALTH_FAKE") ?? "";
            return f !== "" ? JSON.parse(f) : null;
        } catch (e) {
            return null;
        }
    }

    // ---- The battery now (UPower) ------------------------------------------------------
    // The laptop's own battery (not the display device: that one is a sum
    // and has no native path).
    readonly property var device: UPower.devices.values.find(d => d.isLaptopBattery && d.nativePath !== "") ?? null
    readonly property var display: UPower.displayDevice
    readonly property string nativePath: fake ? (fake.nativePath ?? "BAT0") : (device?.nativePath ?? "")
    readonly property bool present: fake !== null || (display?.isLaptopBattery ?? false)
    readonly property int percent: fake ? (fake.percent ?? 0) : Math.round((display?.percentage ?? 0) * 100)
    readonly property string chargeState: {
        if (fake)
            return fake.state ?? "discharging";
        switch (display?.state) {
        case UPowerDeviceState.Charging: return "charging";
        case UPowerDeviceState.FullyCharged: return "full";
        case UPowerDeviceState.PendingCharge: return "pending";
        default: return "discharging";
        }
    }
    readonly property real seconds: fake ? (fake.seconds ?? 0)
        : chargeState === "charging" ? (display?.timeToFull ?? 0) : (display?.timeToEmpty ?? 0)
    readonly property real rate: fake ? (fake.rate ?? 0) : Math.abs(display?.changeRate ?? 0)    // W

    function duration(s) {
        const h = Math.floor(s / 3600);
        const m = Math.round((s % 3600) / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }

    // "On battery · 9.1 W · about 6 h 30 min left"
    readonly property string stateText: {
        const watts = rate >= 0.1 ? " · " + rate.toFixed(1) + " W" : "";
        switch (chargeState) {
        case "charging":
            return "Charging" + watts + (seconds > 0 ? " · " + duration(seconds) + " to full" : "");
        case "full":
            return "Fully charged";
        case "pending":
            return "Plugged in, not charging";
        default:
            return "On battery" + watts + (seconds > 0 ? " · about " + duration(seconds) + " left" : "");
        }
    }

    // ---- Health (sysfs) ------------------------------------------------------------------
    property bool healthKnown: false
    property real designWh: 0            // when new
    property real fullWh: 0              // when full, now
    property real designMah: 0           // charge_* batteries without a voltage: mAh
    property real fullMah: 0
    property int cycles: -1              // -1 = not reported
    property string technology: ""
    property string model: ""
    property string maker: ""

    readonly property bool inWh: designWh > 0 && fullWh > 0
    readonly property bool hasHealth: inWh || (designMah > 0 && fullMah > 0)
    // Full now against new, %, never over 100 (a fresh battery can read a bit above).
    readonly property real healthPercent: !hasHealth ? 0
        : Math.min(100, (inWh ? fullWh / designWh : fullMah / designMah) * 100)
    readonly property real wearPercent: hasHealth ? Math.max(0, 100 - healthPercent) : 0
    // Shown the same way so they add up to 100: one decimal while the wear
    // is under 10 % ("97.3%" / "2.7%"), whole numbers after.
    readonly property int digits: wearPercent < 10 ? 1 : 0
    readonly property real shownHealth: Number(healthPercent.toFixed(digits))
    readonly property string healthText: hasHealth ? String(shownHealth) + "%" : ""
    readonly property string wearText: hasHealth ? String(Number((100 - shownHealth).toFixed(digits))) + "%" : ""
    // Like macOS: "Normal" until it holds under 80 % of what it did new.
    readonly property string condition: !hasHealth ? "" : healthPercent >= 80 ? "Normal" : "Worn"

    function capacityText(wh, mah) {
        return inWh ? wh.toFixed(1) + " Wh" : Math.round(mah) + " mAh";
    }
    readonly property string fullText: hasHealth ? capacityText(fullWh, fullMah) : ""
    readonly property string designText: hasHealth ? capacityText(designWh, designMah) : ""

    FileView {
        id: uevent
        path: root.nativePath !== "" ? root.sysfs + "/" + root.nativePath + "/uevent" : ""
        printErrors: false
        onLoaded: root.readUevent(text())
        onLoadFailed: root.healthKnown = true
    }

    // POWER_SUPPLY_ENERGY_FULL=59170000 lines, µWh / µAh / µV.
    function readUevent(text) {
        const v = {};
        for (const line of String(text).split("\n")) {
            const at = line.indexOf("=");
            if (line.startsWith("POWER_SUPPLY_") && at > 0)
                v[line.slice(13, at)] = line.slice(at + 1).trim();
        }
        const num = k => {
            const n = Number(v[k]);
            return isFinite(n) && n > 0 ? n : 0;
        };
        const volts = num("VOLTAGE_MIN_DESIGN") / 1e6;
        if (num("ENERGY_FULL_DESIGN") > 0) {
            designWh = num("ENERGY_FULL_DESIGN") / 1e6;
            fullWh = num("ENERGY_FULL") / 1e6;
            designMah = 0;
            fullMah = 0;
        } else {
            designMah = num("CHARGE_FULL_DESIGN") / 1e3;
            fullMah = num("CHARGE_FULL") / 1e3;
            designWh = volts > 0 ? designMah * volts / 1000 : 0;
            fullWh = volts > 0 ? fullMah * volts / 1000 : 0;
        }
        const c = Number(v.CYCLE_COUNT);
        cycles = isFinite(c) && c > 0 ? c : -1;
        technology = v.TECHNOLOGY ?? "";
        model = v.MODEL_NAME ?? "";
        maker = v.MANUFACTURER ?? "";
        healthKnown = true;
    }

    // ---- History (UPower over D-Bus) ---------------------------------------------------
    // [{ t: seconds, v: 0-100, plugged: bool }], oldest first, the last
    // Style.batteryGraphHours hours.
    property var history: []
    property double historyAt: 0         // ms, 0 = never
    property string historyError: ""
    property string upowerPath: ""       // the battery's UPower object

    // UPower's object path for a native path: "BAT0" → .../battery_BAT0,
    // with its own escapes ("-" → "_", "." → "x", ":" → "o").
    function escaped(name) {
        return String(name).replace(/-/g, "_").replace(/\./g, "x").replace(/:/g, "o").replace(/[^A-Za-z0-9_]/g, "_");
    }

    function refresh() {
        uevent.reload();
        if (nativePath === "")
            return;
        if (upowerPath === "")
            finder.exec(wrap(["busctl", "--system", "--json=short", "call", "org.freedesktop.UPower",
                              "/org/freedesktop/UPower", "org.freedesktop.UPower", "EnumerateDevices"]));
        else
            askHistory();
    }

    function askHistory() {
        if (asker.running || upowerPath === "")
            return;
        const span = Math.max(1, Style.batteryGraphHours) * 3600;
        asker.exec(wrap(["busctl", "--system", "--json=short", "call", "org.freedesktop.UPower", upowerPath,
                         "org.freedesktop.UPower.Device", "GetHistory", "suu", "charge", String(span), "240"]));
    }

    // Through sh: a missing program is exit 127 with a message, not a failed start.
    function wrap(cmd) {
        return ["sh", "-c", "command -v \"$1\" >/dev/null || { echo \"$1: not installed\" >&2; exit 127; }; exec \"$@\"", "sh"].concat(cmd);
    }

    BusJob {
        id: finder
        onResult: (code, out, err) => {
            let paths = [];
            try {
                paths = JSON.parse(out).data[0];
            } catch (e) {}
            const want = "_" + root.escaped(root.nativePath);
            root.upowerPath = paths.find(p => p.endsWith(want) && p.includes("/battery_"))
                ?? paths.find(p => p.includes("/battery_")) ?? "";
            if (root.upowerPath === "")
                root.historyError = code !== 0 ? (err.trim() || "UPower isn't running") : "UPower doesn't list the battery";
            else
                root.askHistory();
        }
    }

    BusJob {
        id: asker
        onResult: (code, out, err) => {
            if (code !== 0) {
                root.historyError = err.trim() || ("busctl failed (" + code + ")");
                return;
            }
            root.historyError = "";
            root.history = root.parseHistory(out, Date.now() / 1000);
            root.historyAt = Date.now();
        }
    }

    // busctl's JSON: {"type":"a(udu)","data":[[[time, percent, state], ...]]}.
    // UPower's states: 1 charging, 2 discharging, 3 empty, 4 full, 5 plugged
    // in but not charging, 6 waiting to discharge, 0 unknown (= as before).
    function parseHistory(text, now) {
        let rows = [];
        try {
            rows = JSON.parse(text).data[0] ?? [];
        } catch (e) {
            return [];
        }
        const from = now - Math.max(1, Style.batteryGraphHours) * 3600;
        const out = rows
            .filter(r => Array.isArray(r) && r.length >= 3 && r[0] > 0 && r[0] <= now + 60)
            .map(r => ({ t: r[0], v: Math.max(0, Math.min(100, r[1])), s: r[2] }))
            .sort((a, b) => a.t - b.t);
        let plugged = false;
        const list = [];
        for (const p of out) {
            if (p.s === 1 || p.s === 4 || p.s === 5)
                plugged = true;
            else if (p.s === 2 || p.s === 3 || p.s === 6)
                plugged = false;
            list.push({ t: p.t, v: p.v, plugged: plugged });
        }
        // The last point before the window starts says where the line was
        // at its left edge.
        const first = list.findIndex(p => p.t >= from);
        if (first < 0)
            return list.length > 0 ? [Object.assign({}, list[list.length - 1], { t: from })] : [];
        if (first > 0)
            list[first - 1] = Object.assign({}, list[first - 1], { t: from });
        return list.slice(Math.max(0, first - 1));
    }

    // ---- Who looks (the popup) ---------------------------------------------------------
    property int users: 0
    function use(on) {
        users = Math.max(0, users + (on ? 1 : -1));
        if (users > 0)
            refresh();
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.users > 0
        onTriggered: root.refresh()
    }

    // For IPC and tests.
    function status() {
        return JSON.stringify({
            percent: percent, state: chargeState, stateText: stateText,
            health: Math.round(healthPercent * 10) / 10, wear: Math.round(wearPercent * 10) / 10,
            healthText: healthText, wearText: wearText,
            full: fullText, design: designText, cycles: cycles, condition: condition,
            points: history.length, upowerPath: upowerPath, historyError: historyError
        });
    }

    // A busctl call: its answer counts once it has exited and both outputs were read.
    component BusJob: Process {
        id: job
        property int code: -1
        property int parts: 0
        signal result(int code, string out, string err)
        function part() {
            if (++parts === 3)
                result(code, outText.text, errText.text);
        }
        onRunningChanged: if (running) parts = 0
        stdout: StdioCollector {
            id: outText
            onStreamFinished: job.part()
        }
        stderr: StdioCollector {
            id: errText
            onStreamFinished: job.part()
        }
        onExited: c => {
            code = c;
            part();
        }
    }
}
