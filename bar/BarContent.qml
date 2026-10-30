import QtQuick
import qs.common
import qs.services
import qs.osk

// The three islands. Bar.qml puts this in the layer-shell window; it is a
// plain Item so it can also be previewed in a normal window.
//
//  (✿ 1 2 3 · · ▦ | title)      ( 01:49 Thu 15 Oct | ♪ song )      (tray | wifi bt vol bat | 🔔 ⚙ ⏻)
//
// What each island holds, in order, is Style.barLeft / barCenter / barRight
// (Settings → Bar items); `items` below turns each name into its widget.
// An island with nothing in it goes away.
Item {
    id: root

    required property string screenName
    // What gets blurred and takes clicks; the gaps between are see-through.
    readonly property alias leftIsland: leftIsland
    readonly property alias centerIsland: centerIsland
    readonly property alias rightIsland: rightIsland
    // With one bar (Style.barStyle): its glass, which takes the clicks
    // instead of the three islands.
    readonly property Item backdrop: back.slab

    // Not `id: mango`: in `Workspaces { mango: ... }` made from a Component,
    // `mango` would find the widget's own (empty) property first.
    MangoMonitor {
        id: mangoMonitor
        monitor: root.screenName
        reportTiling: true
    }
    // The dock uses this one too (services/Monitors.qml).
    Component.onCompleted: Monitors.register(root.screenName, mangoMonitor)
    Component.onDestruction: {
        if (Monitors.byScreen[root.screenName] === mangoMonitor)
            Monitors.register(root.screenName, null);
    }

    // The lists as text, so the islands are only rebuilt when one really
    // changes (not on every other setting).
    readonly property string leftNames: Style.barLeft.join(" ")
    readonly property string centerNames: Style.barCenter.join(" ")
    readonly property string rightNames: Style.barRight.join(" ")

    function names(text) {
        return text === "" ? [] : text.split(" ");
    }

    readonly property var items: ({
        agents: agentsItem,
        privacy: privacyItem,
        launcher: launcherItem, workspaces: workspacesItem, layout: layoutItem, window: windowItem,
        clock: clockItem, media: mediaItem, tray: trayItem, network: networkItem,
        bluetooth: bluetoothItem, volume: volumeItem, battery: batteryItem,
        notifications: bellItem, controls: controlsItem, power: powerItem, divider: dividerItem,
        recording: recordingItem, focus: focusItem, devices: devicesItem, phone: phoneItem, keyboard: keyboardItem, tailscale: tailscaleItem,
        updates: updatesItem,
        // Wi-Fi, volume and battery as one button (the control center).
        status: statusItem,
        drives: drivesItem,
        screentime: screentimeItem, aiusage: aiusageItem,
        // The timer (services/Timers.qml), while one runs or rings.
        timers: timersItem,
        cpu: cpuItem, memory: memoryItem, temperature: temperatureItem, netspeed: netspeedItem, disk: diskItem
    })

    // Room for the window title: up to the middle island (left or right
    // island), minus everything else in its island.
    function titleRoom(slot) {
        let others = 0;
        let count = 0;
        for (const child of slot.parent?.children ?? []) {
            if (child === slot || !child.visible || child.width <= 0)
                continue;
            others += child.width;
            count++;
        }
        const inside = Style.islandPadding * 2 + others + Style.islandSpacing * count + 16;
        if (slot.island === leftIsland)
            return centerIsland.x - leftIsland.x - inside;
        if (slot.island === rightIsland)
            return root.width - Style.islandSide - (centerIsland.x + centerIsland.width) - inside;
        return Style.titleMaxWidth;
    }

    // How wide an island is without a window title in it (a title gives way
    // to the middle island, so it doesn't count).
    function fixedWidth(island, repeater) {
        if (!island.visible)
            return 0;
        let others = 0;
        let count = 0;
        for (const child of repeater.parent?.children ?? []) {
            if (child.modelData === "window" || !child.visible || child.width <= 0)
                continue;
            others += child.width;
            count++;
        }
        return Style.islandPadding * 2 + others + Style.islandSpacing * Math.max(0, count - 1);
    }

    // Room for the song (Media) in the middle island. That island stays in
    // the screen's middle (what grows out of it starts there), so it may be
    // at most twice as wide as the room on its narrower side, minus
    // everything else in it. Elsewhere the song keeps Style.mediaMaxWidth.
    function mediaRoom(slot) {
        if (slot.island !== centerIsland)
            return Infinity;
        let others = 0;
        let count = 0;
        for (const child of slot.parent?.children ?? []) {
            if (child === slot || !child.visible || child.width <= 0)
                continue;
            others += child.width;
            count++;
        }
        const gap = 8;
        const side = Math.max(fixedWidth(leftIsland, leftRepeater), fixedWidth(rightIsland, rightRepeater));
        const half = root.width / 2 - Style.islandSide - side - gap;
        return 2 * half - Style.islandPadding * 2 - others - Style.islandSpacing * count;
    }

    // The one bar the islands sit in, unless they float apart.
    BarBack {
        id: back
        anchors.fill: parent
    }

    Island {
        id: leftIsland

        x: Style.islandSide
        y: Style.islandTop
        delay: 0
        // The System popup can grow out of any island (SysmonState).
        hidden: IslandState.sysmonCovering && IslandState.sysmonIsland === "left"
        visible: leftRepeater.count > 0
        width: visible ? implicitWidth : 0
        onWidthChanged: IslandState.leftWidth = width

        Repeater {
            id: leftRepeater
            model: root.names(root.leftNames)
            BarSlot { island: leftIsland; components: root.items }
        }
    }

    Island {
        id: centerIsland

        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.islandTop
        delay: Style.dropInDelay
        // In one bar it stays an island of its own (Style.barCenterIsland).
        keepGlass: Style.barCenterIsland
        // A notification grows out of this island and stands in for it.
        hidden: IslandState.takenOver || (IslandState.sysmonCovering && IslandState.sysmonIsland === "center")
        visible: centerRepeater.count > 0
        width: visible ? implicitWidth : 0
        onWidthChanged: IslandState.centerWidth = width

        // Live activities that go on (recording, the focus timer, Claude
        // Code at work), in front of the clock. Part of the island, so
        // IslandState.centerWidth (where stand-ins grow from) counts them.
        ActivitySegment {
            folded: centerIsland.hidden
        }

        Repeater {
            id: centerRepeater
            model: root.names(root.centerNames)
            BarSlot { island: centerIsland; components: root.items }
        }
    }

    Island {
        id: rightIsland

        anchors.right: parent.right
        anchors.rightMargin: Style.islandSide
        y: Style.islandTop
        delay: Style.dropInDelay * 2
        // The control center grows out of this island and stands in for it.
        hidden: IslandState.controlCovering || (IslandState.sysmonCovering && IslandState.sysmonIsland === "right")
        visible: rightRepeater.count > 0
        width: visible ? implicitWidth : 0
        onWidthChanged: IslandState.rightWidth = width

        Repeater {
            id: rightRepeater
            model: root.names(root.rightNames)
            BarSlot { island: rightIsland; components: root.items }
        }
    }

    // ---- The widgets, by name ---------------------------------------------------------
    // (Inside a BarSlot, `parent` is the BarSlot.)
    Component { id: launcherItem; LauncherButton {} }
    Component {
        id: workspacesItem
        Loader {
            // (Style.workspaceStyle: numbers or app icons, or dots.)
            anchors.verticalCenter: parent?.verticalCenter
            sourceComponent: Style.workspaceStyle === "dots" ? workspaceDots : workspaceSlots
        }
    }
    Component { id: workspaceSlots; Workspaces { mango: mangoMonitor } }
    Component { id: workspaceDots; WorkspaceDots { mango: mangoMonitor } }
    Component { id: statusItem; StatusItem {} }
    Component { id: layoutItem; LayoutButton { mango: mangoMonitor } }
    Component {
        id: windowItem
        ActiveWindow {
            // Whatever room is left before the middle island.
            maxWidth: parent ? root.titleRoom(parent) : 0
        }
    }
    Component { id: clockItem; Clock {} }
    Component {
        id: mediaItem
        Media {
            islandHovered: parent?.island?.hovered ?? false
            // Whatever room the neighbours leave (a long song ends in "…").
            maxWidth: parent ? root.mediaRoom(parent) : 0
        }
    }
    Component { id: trayItem; Tray {} }
    Component { id: networkItem; NetworkIcon {} }
    Component { id: bluetoothItem; BluetoothIcon {} }
    Component { id: volumeItem; Volume {} }
    Component { id: batteryItem; Battery {} }
    Component { id: bellItem; Bell {} }
    Component {
        id: controlsItem
        IconButton {
            icon: "tune"
            tip: "Control center"
            tipShortcut: "mine:control-center"
            onClicked: ControlState.toggle("main")
        }
    }
    Component {
        id: powerItem
        IconButton {
            icon: "power_settings_new"
            tip: "Power"
            tipDetail: "Lock, sleep, log out, restart or shut down"
            tipShortcut: "mine:session"
            onClicked: SessionState.toggle()
        }
    }
    Component { id: dividerItem; Divider {} }
    Component { id: recordingItem; RecordingDot {} }
    Component { id: focusItem; FocusButton {} }
    Component { id: devicesItem; DevicesItem {} }
    Component { id: phoneItem; PhoneItem {} }
    Component { id: updatesItem; UpdatesItem {} }
    Component { id: tailscaleItem; TailscaleItem {} }
    Component { id: agentsItem; AgentsItem {} }
    Component { id: keyboardItem; KeyboardButton {} }
    Component { id: cpuItem; Stat { kind: "cpu" } }
    Component { id: memoryItem; Stat { kind: "memory" } }
    Component { id: temperatureItem; Stat { kind: "temperature" } }
    Component { id: netspeedItem; Stat { kind: "netspeed" } }
    Component { id: diskItem; Stat { kind: "disk" } }
    Component { id: privacyItem; PrivacyItem {} }
    Component { id: drivesItem; DrivesItem {} }
    // Screen time and AI usage (services/ScreenTime.qml, services/AiUsage.qml).
    Component { id: screentimeItem; ScreenTimeItem {} }
    Component { id: aiusageItem; AiUsageItem {} }
    // The timer (services/Timers.qml).
    Component { id: timersItem; TimerItem {} }
}
