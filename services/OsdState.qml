pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import qs.common

// What the OSD shows and when. It watches the values themselves (speaker
// volume, mic, screen brightness), so it pops up for any change: keys,
// Noctalia's sliders, scrolling on the bar...
// It stays quiet at start, after a reload (every save of Style.qml) and
// when you switch to another speaker or mic.
// It also shows on/off and named states (stateKinds): Caps Lock, Num Lock,
// Wi-Fi, Bluetooth, power mode, Silent (do not disturb), the keyboard
// layout and the typing language (fcitx5: English / Tiếng Việt,
// Style.osdIme), with the same rules (never for a first-seen value), and
// mango's tiling layout when you switch it (Style.osdTiling).
Singleton {
    id: root

    property string kind: "volume"      // volume | mic | brightness, or one of stateKinds
    property bool shown: false
    // The OSD window exists only while this is true: while shown, plus the
    // time its exit animation takes. Saves memory the rest of the time.
    property bool mapped: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    readonly property real value: kind === "brightness" ? Brightness.value
                                : kind === "mic" ? (source?.audio?.volume ?? 0)
                                : (sink?.audio?.volume ?? 0)
    readonly property bool muted: kind === "mic" ? (source?.audio?.muted ?? false)
                                : kind === "volume" ? (sink?.audio?.muted ?? false)
                                : false
    readonly property string label: kind === "brightness" ? "Brightness"
                                  : kind === "mic" ? root.deviceName(source, "Microphone")
                                  : kind === "ime" ? imeName
                                  : isState ? stateLabels[kind]
                                  : root.deviceName(sink, "Volume")

    // ---- On/off and named states ---------------------------------------------------
    readonly property var stateKinds: ["capslock", "numlock", "wifi", "bluetooth", "power", "dnd", "layout", "tiling", "ime"]
    readonly property var stateLabels: ({
        capslock: "Caps Lock", numlock: "Num Lock", wifi: "Wi-Fi", bluetooth: "Bluetooth",
        power: "Power mode", dnd: "Silent", layout: "Keyboard", tiling: "Tiling", ime: "Typing"
    })
    readonly property bool isState: stateKinds.includes(kind)
    // On (filled chip) or off (outlined chip, dimmed shape).
    readonly property bool active: {
        switch (kind) {
        case "capslock": return capsOn;
        case "numlock": return numOn;
        case "wifi": return Networking.wifiEnabled;
        case "bluetooth": return Bluetooth.defaultAdapter?.enabled ?? false;
        case "power": return PowerProfiles.profile !== PowerProfile.Balanced;
        case "dnd": return Notifs.dnd;
        case "layout": return true;
        case "tiling": return true;
        case "ime": return true;
        }
        return false;
    }
    // The word in the chip.
    readonly property string detail: {
        switch (kind) {
        case "power":
            return PowerProfiles.profile === PowerProfile.PowerSaver ? "Saver"
                 : PowerProfiles.profile === PowerProfile.Performance ? "Performance" : "Balanced";
        case "layout":
            return keyboardLayout;
        case "tiling":
            return Tiling.name(tiling);
        case "ime":
            return imeCode;
        }
        return active ? "On" : "Off";
    }

    function deviceName(node, fallback) {
        return node?.nickname || node?.description || fallback;
    }

    // ---- Where it shows ---------------------------------------------------------------
    // Centered under the middle island, except right after you scroll on the
    // bar's speaker: then right under that icon, where the mouse is. The bar
    // calls anchorTo() just before it changes the volume; the change itself
    // comes back from Pipewire a moment later. Keys never call it, so the
    // volume keys keep the OSD in the middle.
    property string anchorScreen: ""
    property real anchorX: 0
    // This showing sits under the icon (on anchorScreen) instead of the middle.
    property bool anchored: false
    function anchorTo(screenName, x) {
        anchorScreen = screenName;
        anchorX = x;
        anchorFresh.restart();
    }
    Timer {
        id: anchorFresh
        interval: 600
    }

    // Show the OSD for `kind` (also: qs -c mine ipc call osd preview volume).
    function show(k: string) {
        anchored = anchorFresh.running && (k === "volume" || k === "mic");
        kind = k;
        unmapTimer.stop();
        mapped = true;
        shown = true;
        hideTimer.restart();
    }

    PwObjectTracker {
        objects: [root.sink, root.source].filter(node => node !== null)
    }

    Timer {
        id: hideTimer
        interval: Style.osdHideDelay
        onTriggered: {
            root.shown = false;
            unmapTimer.restart();
        }
    }
    Timer {
        id: unmapTimer
        interval: Motion.normal
        onTriggered: root.mapped = false
    }

    // Quiet for the first moment, while everything reports its start values.
    property bool armed: false
    Timer {
        running: true
        interval: 1500
        onTriggered: root.armed = true
    }

    // Last value seen per kind: { id, value, muted }. A different id means
    // another device, which only gets remembered, not shown.
    property var last: ({})

    function seen(k) {
        let id, value, muted;
        if (k === "brightness") {
            if (!Brightness.ready)
                return;
            id = Brightness.device;
            value = Brightness.raw;
            muted = false;
        } else {
            const node = k === "mic" ? source : sink;
            if (!node?.ready || !node.audio)
                return;
            id = node.id;
            value = node.audio.volume;
            muted = node.audio.muted;
        }
        const prev = last[k];
        last[k] = { id: id, value: value, muted: muted };
        if (!armed || prev === undefined || prev.id !== id)
            return;
        // The volume popup is open: the change is already on screen there.
        if (k !== "brightness" && VolumeState.open)
            return;
        // Dimming when idle (services/Idle.qml) and auto brightness
        // (services/AutoBrightness.qml) change it quietly.
        if (k === "brightness" && (Idle.quietBrightness || AutoBrightness.quietBrightness))
            return;
        if (Math.abs(prev.value - value) < 0.0005 && prev.muted === muted)
            return;
        // A click as it changes, like a Mac (not for mute, nor while
        // dragging the control center's slider).
        if (k === "volume" && !muted && Math.abs(prev.value - value) >= 0.0005 && !ControlState.open)
            Sounds.volumeTick();
        show(k);
    }

    onSinkChanged: seen("volume")
    onSourceChanged: seen("mic")

    Connections {
        target: root.sink?.audio ?? null
        function onVolumeChanged() { root.seen("volume"); }
        function onMutedChanged() { root.seen("volume"); }
    }
    Connections {
        target: root.sink
        function onReadyChanged() { root.seen("volume"); }
    }
    Connections {
        target: root.source?.audio ?? null
        function onVolumeChanged() { root.seen("mic"); }
        function onMutedChanged() { root.seen("mic"); }
    }
    Connections {
        target: root.source
        function onReadyChanged() { root.seen("mic"); }
    }
    Connections {
        target: Brightness
        function onRawChanged() { root.seen("brightness"); }
        function onReadyChanged() { root.seen("brightness"); }
    }

    // ---- On/off and named states: same rule as above (remember the first
    // value, show only real changes after the start-up quiet time). While
    // the control center (or for Silent, the notification list) is open the
    // change is already on screen there, so no OSD on top of it.
    function seenState(k, id, value) {
        const prev = last[k];
        last[k] = { id: id, value: value, muted: false };
        if (!armed || prev === undefined || prev.id !== id || prev.value === value)
            return;
        if (["wifi", "bluetooth", "power", "dnd"].includes(k) && IslandState.controlCovering)
            return;
        if (k === "dnd" && Notifs.centerOpen)
            return;
        if (k === "ime" && !Style.osdIme)
            return;
        // Plugged in or out a moment ago: the charger's live activity says
        // the power mode it switched to.
        if (k === "power" && Activities.swallowsPower())
            return;
        show(k);
    }

    Connections {
        target: Networking
        function onWifiEnabledChanged() { root.seenState("wifi", "wifi", Networking.wifiEnabled); }
    }
    readonly property var adapter: Bluetooth.defaultAdapter
    onAdapterChanged: if (adapter) seenState("bluetooth", adapter.dbusPath, adapter.enabled)
    Connections {
        target: root.adapter
        function onEnabledChanged() { root.seenState("bluetooth", root.adapter.dbusPath, root.adapter.enabled); }
    }
    Connections {
        target: PowerProfiles
        function onProfileChanged() { root.seenState("power", "power", PowerProfiles.profile); }
    }
    // Silent comes back from the saved notification list a moment after
    // start: only count it once that has happened.
    Connections {
        target: Notifs
        function onDndChanged() { if (Notifs.loaded) root.seenState("dnd", "dnd", Notifs.dnd); }
        function onLoadedChanged() { if (Notifs.loaded) root.seenState("dnd", "dnd", Notifs.dnd); }
    }

    // Keyboard layout: told by MangoMonitor (mango's `keyboardlayout`); the
    // same for every screen, so repeats are ignored.
    property string keyboardLayout: ""
    function noteLayout(name) {
        if (name === "")
            return;
        keyboardLayout = name;
        seenState("layout", "layout", name);
    }

    // Typing language: fcitx5's tray item (id "Fcitx"; Super+Space switches).
    // Its icon says which input method is on: "fcitx_bamboo" = Bamboo
    // (Vietnamese), "input-keyboard-symbolic" (or "input-keyboard") = the
    // plain keyboard, English here. The tooltip's name is in the system's
    // language, so it only backs up the icon for Vietnamese. Anything else
    // (another input method, the icon missing for a moment while Quickshell
    // reads it again) is "": the tray keeps fcitx's own icon and nothing is
    // shown or remembered. A new fcitx (restarted) counts as another device:
    // its first value is only remembered.
    readonly property var imeItem: SystemTray.items.values.find(i => i.id === "Fcitx") ?? null
    readonly property string imeCode: {
        const item = imeItem;
        if (!item)
            return "";
        // "image://icon/fcitx_bamboo" or "image://icon/name?path=…".
        const icon = (item.icon ?? "").replace(/^image:\/\/icon\//, "").replace(/\?.*$/, "").toLowerCase();
        if (/bamboo|unikey|vietnam/.test(icon))
            return "VI";
        if (/^input-keyboard(-symbolic)?$/.test(icon))
            return "EN";
        if (icon !== "" && /^bamboo$|unikey/i.test(item.tooltipTitle ?? ""))
            return "VI";
        return "";
    }
    readonly property string imeName: imeCode === "VI" ? "Tiếng Việt" : imeCode === "EN" ? "English" : ""
    onImeCodeChanged: if (imeCode !== "") seenState("ime", imeItem, imeCode)

    // Tiling layout: told by the bar's MangoMonitor, only when you switch it
    // on the same workspace (Super+Alt+J, the bar's layout button).
    property string tiling: ""
    // Its icon, for the OSD's shape.
    readonly property string tilingIcon: Tiling.icon(tiling)
    function noteTiling(symbol) {
        tiling = symbol;
        if (armed && Style.osdTiling)
            show("tiling");
    }

    // Caps Lock / Num Lock: the keyboard LEDs in sysfs. The kernel sends no
    // event when they change (no udev "change" for LEDs, no
    // brightness_hw_changed on these, and sysfs can't be watched), so they
    // are read 4 times a second: two tiny reads, nothing else.
    // MINE_OSD_LEDS (tests) points at a fake /sys/class/leds.
    readonly property string ledsDir: Quickshell.env("MINE_OSD_LEDS") || "/sys/class/leds"
    property string capsPath: ""
    property string numPath: ""
    property bool capsOn: false
    property bool numOn: false

    Process {
        running: true
        command: ["sh", "-c", 'for f in "$1"/*::capslock "$1"/*::numlock; do [ -e "$f/brightness" ] && echo "$f"; done', "leds", root.ledsDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.trim().split("\n").filter(l => l !== "");
                root.capsPath = found.find(l => l.endsWith("::capslock")) ?? "";
                root.numPath = found.find(l => l.endsWith("::numlock")) ?? "";
            }
        }
    }
    FileView {
        id: capsFile
        path: root.capsPath !== "" ? root.capsPath + "/brightness" : ""
        printErrors: false
        onLoaded: {
            root.capsOn = parseInt(text()) > 0;
            root.seenState("capslock", root.capsPath, root.capsOn);
        }
    }
    FileView {
        id: numFile
        path: root.numPath !== "" ? root.numPath + "/brightness" : ""
        printErrors: false
        onLoaded: {
            root.numOn = parseInt(text()) > 0;
            root.seenState("numlock", root.numPath, root.numOn);
        }
    }
    // Caps / Num Lock only change on a key press: read them only while
    // there's been input in the last couple of seconds (reading them all
    // the time was most of the shell's CPU while idle).
    IdleMonitor {
        id: typing
        timeout: 2
        respectInhibitors: false
    }
    Timer {
        running: (root.capsPath !== "" || root.numPath !== "") && !typing.isIdle
        interval: 250
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.capsPath !== "")
                capsFile.reload();
            if (root.numPath !== "")
                numFile.reload();
        }
    }

    // The values each state has right now, recorded once everything has
    // reported in (so a change during the quiet time isn't lost either).
    onArmedChanged: {
        if (!armed)
            return;
        if (last.wifi === undefined)
            seenState("wifi", "wifi", Networking.wifiEnabled);
        if (adapter && last.bluetooth === undefined)
            seenState("bluetooth", adapter.dbusPath, adapter.enabled);
        if (last.power === undefined)
            seenState("power", "power", PowerProfiles.profile);
        if (Notifs.loaded && last.dnd === undefined)
            seenState("dnd", "dnd", Notifs.dnd);
    }
}
