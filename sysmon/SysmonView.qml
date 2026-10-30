import QtQuick
import Quickshell
import qs.common
import qs.services

// The System popup. A small card that grows out of the island holding the
// stat you clicked (MorphCard, like the calendar and the control center):
//
//      ╭──────────────────────────────────╮
//      │   ◔ 12%   ◑ 58%   ◔ 40°   ◕ 23%  │   hover a ring: the detail
//      │    CPU     RAM     Temp    Disk  │
//      │  ▁▂▂▃▅▃▂▂▁▂▃▄▃▂▁▂▃▂  CPU · 1.3 GHz │   the last 40 reads
//      │  Apps                CPU   Memory│   click CPU / Memory to sort
//      │  [icon] Claude        1.4%   987M│   hover: ✕ ends it
//      │  …                               │
//      │  Listening                       │   ports your programs listen on
//      │  (◍) next-server  :20128  all i… │   click opens it in the browser;
//      │  ↓ 1.2 MB/s  ↑ 40 KB/s     btop ↗│   hover: copy, ✕ stops it
//      ╰──────────────────────────────────╯
//
// Esc or a click outside closes it; C / M sort the apps. Plain QtQuick
// (plus SysStats and SysmonState), so it can be previewed.
Item {
    id: root

    // Where the island it grows out of is (left | center | right) and how
    // wide it is right now: where we start and end.
    property string island: "right"
    property real startWidth: 300
    property bool open: false

    // While true the bar hides the real island.
    readonly property bool covering: morph.covering
    // Fully back in the island: the window can go.
    readonly property bool settled: morph.settled
    readonly property alias cardItem: morph.card

    signal closeRequested()

    readonly property real pad: 16
    readonly property real inner: Style.sysmonWidth - pad * 2
    // The app list's columns (ProcessRow uses the same).
    readonly property real cpuColumn: 52
    readonly property real memColumn: 52
    readonly property real endColumn: 28
    // Listening ports shown before "+N more".
    readonly property int listenRows: 6

    function focusKeys() {
        keys.forceActiveFocus();
    }

    // ---- Which app a program belongs to (for its icon and name) -------------------
    // By the program each desktop entry runs ("Discord", "foot", "zen-bin"),
    // its window class and its id; else Quickshell's fuzzy lookup.
    readonly property var programs: {
        const map = {};
        for (const e of DesktopEntries.applications.values) {
            const cmd = (e.command ?? []).filter(a => !/^[A-Za-z_][A-Za-z0-9_]*=/.test(a) && a !== "env");
            const keys = [cmd[0] ? cmd[0].split("/").pop() : "", e.startupClass ?? "", e.id ?? ""];
            for (const k of keys) {
                const key = k.toLowerCase().replace(/\.desktop$/, "");
                if (key !== "" && !(key in map))
                    map[key] = e;
            }
        }
        return map;
    }
    // Programs without an app of their own, by a nicer name.
    readonly property var nicknames: ({ qs: "Quickshell", quickshell: "Quickshell", claude: "Claude Code" })
    function nameFor(name) {
        return nicknames[name] ?? appFor(name)?.name ?? name;
    }
    function appFor(name) {
        if (!name)
            return null;
        const key = name.toLowerCase();
        const plain = key.replace(/(-bin|-wrapped|\.bin|\.real)$/, "");
        return programs[key] ?? programs[plain] ?? DesktopEntries.heuristicLookup(name) ?? null;
    }

    // ---- A ring's detail, under the rings while hovered ---------------------------------
    property Item tipFor: null
    function hoverRing(ring, on) {
        if (on)
            tipFor = ring;
        else if (tipFor === ring)
            tipFor = null;
    }
    readonly property string tipText: {
        switch (tipFor) {
        case cpuRing:
            return [SysStats.mhz > 0 ? (SysStats.mhz / 1000).toFixed(1) + " GHz" : "",
                    SysStats.load !== "" ? "load " + SysStats.load : "",
                    SysStats.coreCount > 0 ? SysStats.coreCount + " threads" : ""].filter(t => t !== "").join("  ·  ");
        case ramRing:
            return SysStats.size(SysStats.memUsed) + " of " + SysStats.size(SysStats.memTotal)
                 + (SysStats.swapTotal > 0 ? "  ·  swap " + SysStats.size(SysStats.swapUsed) : "");
        case tempRing:
            return SysStats.tempSource !== "" ? SysStats.tempSource + " sensor" : "";
        case diskRing:
            return "/  " + SysStats.size(SysStats.diskUsed) + " of " + SysStats.size(SysStats.diskTotal);
        }
        return "";
    }

    MorphCard {
        id: morph

        anchors.fill: parent
        grow: root.island === "left" ? "left" : root.island === "right" ? "right" : "center"
        fromX: root.island === "left" ? Style.islandSide
             : root.island === "right" ? width - Style.islandSide - root.startWidth
             : (width - root.startWidth) / 2
        fromY: Style.islandTop
        fromWidth: root.startWidth
        toWidth: Style.sysmonWidth
        toHeight: content.implicitHeight + root.pad * 2
        radius: Style.sysmonRadius
        glassOpacity: Style.sysmonOpacity
        open: root.open

        // Clicks on the card stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        // Esc closes; C / M sort the apps.
        Item {
            id: keys
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape)
                    root.closeRequested();
                else if (event.key === Qt.Key_C)
                    SysStats.procSort = "cpu";
                else if (event.key === Qt.Key_M)
                    SysStats.procSort = "memory";
                else
                    return;
                event.accepted = true;
            }
        }

        Column {
            id: content
            x: root.pad
            y: root.pad
            width: root.inner
            spacing: 14

            // ---- Rings ----------------------------------------------------------------------
            Item {
                width: parent.width
                height: rings.height

                Row {
                    id: rings
                    // Spread over the whole width, the same gap between each.
                    readonly property real gap: (parent.width - cpuRing.width * 4) / 3
                    spacing: gap

                    Ring {
                        id: cpuRing
                        objectName: "ring-cpu"
                        value: SysStats.cpu
                        text: SysStats.cpuReady ? Math.round(SysStats.cpu * 100) + "%" : "…"
                        label: "CPU"
                        warn: SysStats.cpu * 100 >= Style.statsWarnCpu
                        onHoveredChanged: root.hoverRing(cpuRing, hovered)
                    }
                    Ring {
                        id: ramRing
                        objectName: "ring-ram"
                        value: SysStats.memory
                        text: SysStats.memTotal > 0 ? Math.round(SysStats.memory * 100) + "%" : "…"
                        label: "RAM"
                        warn: SysStats.memory * 100 >= Style.statsWarnMemory
                        onHoveredChanged: root.hoverRing(ramRing, hovered)
                    }
                    Ring {
                        id: tempRing
                        objectName: "ring-temp"
                        value: SysStats.temp / 100
                        text: SysStats.tempSource !== "" ? Math.round(SysStats.temp) + "°" : "…"
                        label: "Temp"
                        warn: SysStats.temp >= Style.statsWarnTemp
                        onHoveredChanged: root.hoverRing(tempRing, hovered)
                    }
                    Ring {
                        id: diskRing
                        objectName: "ring-disk"
                        value: SysStats.disk
                        text: SysStats.diskTotal > 0 ? Math.round(SysStats.disk * 100) + "%" : "…"
                        label: "Disk"
                        warn: SysStats.disk * 100 >= Style.statsWarnDisk
                        onHoveredChanged: root.hoverRing(diskRing, hovered)
                    }
                }
            }

            // ---- CPU graph (the hovered ring's detail floats over it) --------------------
            Item {
                width: parent.width
                height: 56

                Graph {
                    anchors.fill: parent
                    values: SysStats.cpuHistory
                    color: SysStats.cpu * 100 >= Style.statsWarnCpu ? Colors.error : Colors.primary
                }

                StyledText {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: "CPU" + (SysStats.mhz > 0 ? "  ·  " + (SysStats.mhz / 1000).toFixed(1) + " GHz" : "")
                    role: "caption"
                    font.features: ({ "tnum": 1 })
                    color: Colors.textOnSurfaceVariant
                    opacity: root.tipText === "" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                // The detail of the ring under the pointer, right under it.
                Rectangle {
                    id: tip
                    readonly property real want: root.tipFor ? root.tipFor.x + root.tipFor.width / 2 - width / 2 : 0
                    x: Math.max(0, Math.min(parent.width - width, want))
                    y: -6
                    width: tipLabel.implicitWidth + 20
                    height: 24
                    radius: height / 2
                    color: Colors.surfaceContainerHighest
                    opacity: root.tipText !== "" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    Behavior on x {
                        enabled: tip.opacity > 0.5
                        NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                    }

                    StyledText {
                        id: tipLabel
                        anchors.centerIn: parent
                        text: root.tipText
                        role: "caption"
                        font.features: ({ "tnum": 1 })
                    }
                }
            }

            // ---- Apps -----------------------------------------------------------------------
            Column {
                width: parent.width
                spacing: 2

                // "Apps" and the column headers; click CPU or Memory to sort.
                Item {
                    width: parent.width
                    height: 20

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Apps"
                        role: "label"
                        color: Colors.textOnSurfaceVariant
                    }
                    SortHeader {
                        anchors.right: memHeader.left
                        width: root.cpuColumn
                        label: "CPU"
                        value: "cpu"
                    }
                    SortHeader {
                        id: memHeader
                        anchors.right: parent.right
                        anchors.rightMargin: root.endColumn
                        width: root.memColumn
                        label: "Memory"
                        value: "memory"
                    }
                }

                Item {
                    width: parent.width
                    height: rows.height

                    Column {
                        id: rows
                        width: parent.width
                        opacity: SysStats.processesReady ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.contentIn } }

                        Repeater {
                            model: Math.max(1, Style.sysmonProcessCount)

                            ProcessRow {
                                required property int index
                                width: rows.width
                                proc: SysStats.processes[index] ?? null
                                entry: root.appFor(proc?.name)
                                name: proc ? root.nameFor(proc.name) : ""
                                sortBy: SysStats.procSort
                                cpuColumn: root.cpuColumn
                                memColumn: root.memColumn
                                endColumn: root.endColumn
                            }
                        }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: !SysStats.processesReady
                        text: "Measuring…"
                        color: Colors.textOnSurfaceVariant
                    }
                }
            }

            // ---- Ports your programs listen on (dev servers) ------------------------------
            // Only when there are some; at most `listenRows`, then "+N more".
            Column {
                width: parent.width
                spacing: 2
                visible: SysmonState.listening.length > 0

                Item {
                    width: parent.width
                    height: 20

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Listening"
                        role: "label"
                        color: Colors.textOnSurfaceVariant
                    }
                    StyledText {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        visible: SysmonState.listening.length > root.listenRows
                        text: "+" + (SysmonState.listening.length - root.listenRows) + " more"
                        role: "caption"
                        color: Colors.textOnSurfaceVariant
                    }
                }

                Repeater {
                    model: Math.min(root.listenRows, SysmonState.listening.length)

                    ListenRow {
                        required property int index
                        width: parent.width
                        listener: SysmonState.listening[index] ?? null
                        entry: root.appFor(listener?.name)
                        name: listener ? root.nameFor(listener.name) : ""
                        onOpened: root.closeRequested()
                    }
                }
            }

            // ---- Network, and btop ---------------------------------------------------------
            Item {
                width: parent.width
                height: 22

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Speed {
                        arrow: "arrow_downward"
                        value: SysStats.netReady ? SysStats.speed(SysStats.down) : "…"
                    }
                    Speed {
                        arrow: "arrow_upward"
                        value: SysStats.netReady ? SysStats.speed(SysStats.up) : "…"
                    }
                }

                Clickable {
                    anchors.right: parent.right
                    visible: SysStats.monitorCommand !== "" || Style.statsClickCommand !== ""
                    implicitHeight: 24
                    padding: 8
                    spacing: 3
                    onClicked: {
                        SysStats.openMonitor();
                        root.closeRequested();
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "btop"
                        role: "label"
                        color: Colors.primary
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "arrow_outward"
                        size: 14
                        color: Colors.primary
                    }
                }
            }
        }
    }

    // ---- Small parts --------------------------------------------------------------------------
    // A column header of the app list: click to sort by it.
    component SortHeader: MouseArea {
        id: header
        property string label: ""
        property string value: ""
        readonly property bool chosen: SysStats.procSort === value

        anchors.verticalCenter: parent.verticalCenter
        height: 20
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: SysStats.procSort = value

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "arrow_drop_down"
                size: 16
                color: Colors.primary
                opacity: header.chosen ? 1 : 0
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: header.label
                role: "caption"
                weight: header.chosen ? 700 : 600
                color: header.chosen ? Colors.primary : header.containsMouse ? Colors.textOnSurface : Colors.textOnSurfaceVariant
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }
    }

    // ↓ 675 KB/s
    component Speed: Row {
        property string arrow: ""
        property string value: ""
        spacing: 3

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: parent.arrow
            size: 14
            color: Colors.textOnSurfaceVariant
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            role: "caption"
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }
    }
}
