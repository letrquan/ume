import QtQuick
import qs.common
import qs.services

// One system number on the bar: CPU, memory, temperature, network speed or
// disk (`kind`). An icon and the number; hovering slides out a bit more.
// Turns red past its warning level (Style, Bar items). Click: the System
// popup (graphs, each core, every disk, the busiest processes), grown out
// of the island this item is on.
Clickable {
    id: root

    property string kind: "cpu"     // cpu | memory | temperature | netspeed | disk

    readonly property bool high: {
        switch (kind) {
        case "cpu": return SysStats.cpu * 100 >= Style.statsWarnCpu;
        case "memory": return SysStats.memory * 100 >= Style.statsWarnMemory;
        case "temperature": return SysStats.temp >= Style.statsWarnTemp;
        case "disk": return SysStats.disk * 100 >= Style.statsWarnDisk;
        }
        return false;
    }
    readonly property string icon: {
        switch (kind) {
        case "cpu": return "memory";
        case "memory": return "memory_alt";
        case "temperature": return "device_thermostat";
        case "netspeed": return "arrow_downward";
        case "disk": return "hard_drive";
        }
        return "monitoring";
    }
    readonly property string value: {
        switch (kind) {
        case "cpu":
            return SysStats.cpuReady ? Math.round(SysStats.cpu * 100) + "%" : "…";
        case "memory":
            return SysStats.memTotal === 0 ? "…"
                 : Style.statsMemoryAs === "gb" ? (SysStats.memUsed / SysStats.gb).toFixed(1) + "G"
                 : Math.round(SysStats.memory * 100) + "%";
        case "temperature":
            return SysStats.tempSource === "" ? "…" : Math.round(SysStats.temp) + "°";
        case "netspeed":
            return SysStats.netReady ? SysStats.rate(SysStats.down) : "…";
        case "disk":
            return SysStats.diskTotal === 0 ? "…" : Math.round(SysStats.disk * 100) + "%";
        }
        return "";
    }
    // Slides out on hover.
    readonly property string more: {
        switch (kind) {
        case "cpu":
            return SysStats.load !== "" ? "load " + SysStats.load : "";
        case "memory":
            return SysStats.memTotal === 0 ? ""
                 : (Style.statsMemoryAs === "gb" ? Math.round(SysStats.memory * 100) + "%" : SysStats.size(SysStats.memUsed))
                   + " of " + SysStats.size(SysStats.memTotal)
                   + (SysStats.swapUsed > 1e8 ? " · swap " + SysStats.size(SysStats.swapUsed) : "");
        case "temperature":
            return SysStats.tempSource;
        case "netspeed":
            return SysStats.netReady ? "↑ " + SysStats.rate(SysStats.up) : "";
        case "disk":
            return SysStats.diskTotal === 0 ? "" : SysStats.size(SysStats.diskTotal - SysStats.diskUsed) + " free";
        }
        return "";
    }

    // Only what's on the bar is read (see SysStats).
    property string held: ""
    onKindChanged: {
        if (held !== "")
            SysStats.release(held);
        held = kind;
        SysStats.hold(kind);
    }
    Component.onCompleted: if (held === "") { held = kind; SysStats.hold(kind); }
    Component.onDestruction: if (held !== "") SysStats.release(held)

    spacing: 3
    // What the bar doesn't say: the exact number (the bar rounds it, and
    // its hover text has the rest), and that a click opens the System popup.
    tip: {
        switch (kind) {
        case "cpu": return "Processor · " + (SysStats.cpu * 100).toFixed(1) + "%";
        case "memory": return "Memory · " + (SysStats.memory * 100).toFixed(1) + "%";
        case "temperature": return "Temperature · " + SysStats.temp.toFixed(1) + " °C";
        case "netspeed": return "Network";
        case "disk": return "Disk · " + (SysStats.disk * 100).toFixed(1) + "% used";
        }
        return "";
    }
    tipDetail: {
        if (Tooltips.source !== root)
            return "";
        let line = "";
        switch (kind) {
        case "cpu":
            line = SysStats.coreCount > 0 ? SysStats.coreCount + " threads" + (SysStats.mhz > 0 ? " · " + (SysStats.mhz / 1000).toFixed(2) + " GHz" : "") : "";
            break;
        case "memory":
            line = SysStats.memTotal > 0 ? SysStats.size(SysStats.memTotal - SysStats.memUsed) + " free" : "";
            break;
        case "temperature":
            line = "Red from " + Style.statsWarnTemp + " °C";
            break;
        case "netspeed":
            line = "↓ " + SysStats.rate(SysStats.down) + "B/s   ↑ " + SysStats.rate(SysStats.up) + "B/s";
            break;
        case "disk":
            line = SysStats.diskTotal > 0 ? SysStats.size(SysStats.diskUsed) + " of " + SysStats.size(SysStats.diskTotal) : "";
            break;
        }
        return (line !== "" ? line + "\n" : "") + "Click: the System popup";
    }
    onClicked: SysmonState.toggle(SysmonState.islandOf(kind))

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        size: Style.iconSize - 2
        color: root.high ? Colors.error : Colors.textOnSurfaceVariant
    }

    // Never narrower than a typical number, so the bar doesn't twitch
    // every time it changes.
    StyledText {
        id: number
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(implicitWidth, widest.advanceWidth)
        text: root.value
        font.features: ({ "tnum": 1 })
        color: root.high ? Colors.error : Colors.textOnSurface

        Behavior on color { ColorAnimation { duration: Motion.normal } }
    }

    TextMetrics {
        id: widest
        font: number.font
        text: root.kind === "netspeed" ? "8.8M" : root.kind === "temperature" ? "88°" : "88%"
    }

    Reveal {
        anchors.verticalCenter: parent.verticalCenter
        shown: root.containsMouse && root.more !== ""

        StyledText {
            leftPadding: 3
            text: root.more
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }
    }
}
