pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.common

// The control center: whether it's open, which page, and every action it
// takes (Wi-Fi, Bluetooth, power mode, sound devices, volume, brightness).
// All actions go through here so MINE_CC_DRYRUN=1 (tests) only prints them.
// It never comes back open after a reload or restart.
Singleton {
    id: root

    property bool open: false
    property bool mapped: false
    property string page: "main"        // main | wifi | bluetooth | audio | phone

    readonly property bool dryRun: Quickshell.env("MINE_CC_DRYRUN") === "1"

    function toggle(p) {
        const want = p || "main";
        if (open && page === want)
            close();
        else
            show(want);
    }

    function show(p) {
        page = p || "main";
        unmap.stop();
        // open first: the window is created the moment `mapped` turns on,
        // and must see the panel open already.
        open = true;
        mapped = true;
    }

    function close() {
        if (!open)
            return;
        open = false;
        unmap.restart();
    }

    // The window goes once the control center reports it's back in the
    // island (settled). This is only a safety net in case it never does.
    Timer {
        id: unmap
        interval: Motion.morphOut + 1500
        onTriggered: root.settled()
    }

    function settled() {
        if (open || !mapped)
            return;
        unmap.stop();
        // The window goes a moment later, not in the very frame the island
        // starts fading back in: letting go of a window stalls the shell
        // for ~50 ms, which made that fade stutter.
        release.restart();
        page = "main";
    }

    Timer {
        id: release
        interval: Motion.contentIn + 80
        onTriggered: if (!root.open) root.mapped = false
    }

    // ---- Things the pages show ---------------------------------------------------
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevice: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var wifiNetwork: wifiDevice?.networks.values.find(n => n.connected) ?? null
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var btConnected: adapter ? adapter.devices.values.filter(d => d.connected) : []
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio && !isSpeakerEq(n))
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio && !(n.name ?? "").endsWith(".monitor"))

    // The speaker EQ (~/.config/pipewire/filter-chain.conf.d/speaker-eq.conf)
    // runs as its own PipeWire filter in front of the built-in speakers. Its
    // two nodes ("speaker-eq", "speaker-eq.out") are neither a device nor an
    // app, so the lists leave them out. It's on while that filter runs; the
    // switch flips at once and follows PipeWire when the filter comes or goes.
    function isSpeakerEq(node) {
        return (node?.name ?? "").startsWith("speaker-eq");
    }
    readonly property bool speakerEqRunning: Pipewire.nodes.values.some(n => n.name === "speaker-eq")
    property int speakerEqAsked: -1     // -1: nothing asked, 0: off, 1: on
    readonly property bool speakerEq: speakerEqAsked >= 0 ? speakerEqAsked === 1 : speakerEqRunning
    onSpeakerEqRunningChanged: speakerEqAsked = -1
    Timer {
        id: speakerEqSettle
        interval: 4000
        onTriggered: root.speakerEqAsked = -1
    }

    function nodeName(node) {
        return node?.nickname || node?.description || node?.name || "";
    }

    // ---- Actions -----------------------------------------------------------------------
    function act(what, fn) {
        if (dryRun)
            console.log("control (dry run):", what);
        else
            fn();
    }

    function setWifi(on) {
        act("wifi " + on, () => Networking.wifiEnabled = on);
    }
    function connectNetwork(network, psk) {
        act("connect " + network.name, () => psk ? network.connectWithPsk(psk) : network.connect());
    }
    function disconnectNetwork(network) {
        act("disconnect " + network.name, () => network.disconnect());
    }
    function setScanning(on) {
        if (wifiDevice)
            act("wifi scan " + on, () => wifiDevice.scannerEnabled = on);
    }

    function setBluetooth(on) {
        if (adapter)
            act("bluetooth " + on, () => adapter.enabled = on);
    }
    function setDiscovering(on) {
        if (adapter && adapter.enabled)
            act("bluetooth scan " + on, () => adapter.discovering = on);
    }
    // Click on a device: connect, disconnect, or pair then connect.
    function useDevice(device) {
        act("bluetooth device " + device.name, () => {
            if (device.connected)
                device.disconnect();
            else if (device.paired)
                device.connect();
            else {
                device.trusted = true;
                device.pair();
            }
        });
    }

    readonly property var profiles: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
    function nextProfile() {
        const list = PowerProfiles.hasPerformanceProfile ? profiles : profiles.slice(0, 2);
        const next = list[(list.indexOf(PowerProfiles.profile) + 1) % list.length];
        act("power profile " + next, () => PowerProfiles.profile = next);
    }

    function setVolume(node, value) {
        if (node?.audio)
            act("volume " + value.toFixed(2), () => {
                node.audio.volume = Math.max(0, Math.min(1, value));
                if (node.audio.muted && value > 0)
                    node.audio.muted = false;
            });
    }
    function toggleMute(node) {
        if (node?.audio)
            act("mute " + nodeName(node), () => node.audio.muted = !node.audio.muted);
    }
    function useSink(node) {
        act("output " + nodeName(node), () => Pipewire.preferredDefaultAudioSink = node);
    }
    function useSource(node) {
        act("input " + nodeName(node), () => Pipewire.preferredDefaultAudioSource = node);
    }
    // enable/disable too, so it stays the way you left it after a restart.
    function setSpeakerEq(on) {
        speakerEqAsked = on ? 1 : 0;
        speakerEqSettle.restart();
        act("speaker eq " + on, () => Quickshell.execDetached(["systemctl", "--user", on ? "enable" : "disable", "--now", "filter-chain.service"]));
    }
    // While dragging, brightnessctl runs at most every 60 ms.
    function setBrightness(value) {
        pendingBrightness = value;
        if (!brightnessTimer.running)
            brightnessTimer.start();
    }
    property real pendingBrightness: 0
    Timer {
        id: brightnessTimer
        interval: 60
        onTriggered: root.act("brightness " + root.pendingBrightness.toFixed(2), () => Brightness.set(root.pendingBrightness))
    }

    // Volume and mic levels only fill in for tracked nodes.
    PwObjectTracker {
        objects: root.sinks.concat(root.sources)
    }
}
