pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.common

// Live activities.
//
// Moments: something just happened, so the middle island grows for a couple
// of seconds (Style.activityDuration) to say it, then shrinks back
// (activity/MomentWindow.qml, a MorphCard like the notification island):
//
//      ╭───────────────────────────────────────╮
//      │ (⚡) Charging · 1h 20m to full  ▮▮▯ 36% │
//      ╰───────────────────────────────────────╯
//
//   charging    plugged in / unplugged (the power mode it switched to with it)
//   bluetooth   headphones or a speaker connected / gone, with its battery
//   screenshot  saved: the picture (click opens it); the notification with
//               Open / Edit / Delete still goes to the list, quietly
//   copy        what you copied (text, a picture, a color); also the
//               color picker and "copy text" from a screenshot
//   wifi        connected / disconnected (turning Wi-Fi on or off stays the
//               OSD's)
//   focus       the focus timer's "Break time" / "Back to work"
// One at a time. A notification wins: a moment showing ends at once, and new
// ones wait (a few seconds at most) until the notification island is back.
// While a panel is open (launcher, control center, calendar, …), or a
// window is fullscreen, moments are dropped: what they'd say is on screen
// already, or you're busy.
//
// The bubble: a segment at the front of the middle island (bar/
// ActivitySegment.qml) while something goes on: screen recording (click
// stops it), the focus timer (click pauses), Claude Code sessions working
// or waiting for you (click goes to one).
//
// Try them: qs -c mine ipc call activities preview <kind>
//   charging unplugged bluetooth screenshot copy picture color ocr wifi
//   wifioff focus · recording timer agents (bubble, for 8 s)
Singleton {
    id: root

    readonly property bool enabled: Style.activitiesEnabled

    // ---- Moments ---------------------------------------------------------------------------
    property var moment: null           // showing (or growing / about to)
    property var queue: []              // waiting for the notification island
    property int revision: 0            // the showing one got new content (same kind again)
    property bool mapped: false         // the window exists (shell.qml)
    property bool cardUp: false         // the card is out of the island (until it settles back)
    // A moment holds the middle island: the notification island waits.
    readonly property bool busy: moment !== null || cardUp

    // Nothing at start: what's already plugged in or connected isn't news.
    property bool armed: false
    Timer {
        interval: 3000
        running: true
        onTriggered: root.armed = true
    }

    function kindOn(kind) {
        switch (kind) {
        case "charging": return Style.activityCharging;
        case "bluetooth": return Style.activityBluetooth;
        case "screenshot": return Style.activityScreenshot;
        case "copy": return Style.activityClipboard;
        case "wifi": return Style.activityWifi;
        case "focus": return Style.activityFocus;
        }
        return false;
    }

    // A panel owns the screen (or the middle island), or a window is
    // fullscreen: no moments.
    readonly property bool blocked: LauncherState.open || ClipboardState.open || CalendarState.open
        || NowPlayingState.open
        || ControlState.open || OverviewState.open || SessionState.open || SwitcherState.open
        || CheatSheetState.open || Wallpaper.pickerOpen || Screenshot.active
        || (SysmonState.open && SysmonState.island === "center") || Notifs.fullscreenQuiet
    // The notification island is out, or about to be.
    readonly property bool notifUp: Notifs.popups.length > 0 || IslandState.notifCovering

    // Show a moment: { kind, … } (see view()). True if it shows or waits its
    // turn; false if it won't (off, blocked, too early) so the caller can
    // tell it another way (a notification).
    function show(m) {
        if (!enabled || (!m.preview && (!armed || !kindOn(m.kind))) || blocked)
            return false;
        m.at = Date.now();
        if (moment && moment.kind === m.kind && !cardClosing) {
            moment = m;
            revision++;
            return true;
        }
        if (moment || cardUp || notifUp) {
            queue = queue.filter(q => q.kind !== m.kind).concat([m]);
            return true;
        }
        start(m);
        return true;
    }

    function start(m) {
        release.stop();
        cardClosing = false;
        cardUp = true;
        moment = m;
        mapped = true;
    }

    // Its time is up, it was clicked, or something else needs the island.
    property bool cardClosing: false
    function done() {
        if (moment)
            cardClosing = true;
        moment = null;
    }

    // The card is back in the island (MomentWindow).
    function settled() {
        cardUp = false;
        cardClosing = false;
        Qt.callLater(next);
    }

    function next() {
        if (moment || cardUp)
            return;
        const now = Date.now();
        queue = queue.filter(q => now - q.at < 8000);
        if (queue.length > 0 && !blocked && !notifUp && enabled) {
            const m = queue[0];
            queue = queue.slice(1);
            start(m);
            return;
        }
        // The window goes a moment later, not in the frame the island fades
        // back in (letting go of a window stalls the shell for ~50 ms).
        release.restart();
    }
    Timer {
        id: release
        interval: Motion.contentIn + 80
        onTriggered: if (!root.moment && !root.cardUp) root.mapped = false
    }
    // Safety: a card that never reports back (its window failed).
    Timer {
        running: root.cardUp && root.moment === null
        interval: Motion.morphOut + 1500
        onTriggered: root.settled()
    }

    onBlockedChanged: {
        if (blocked) {
            done();
            queue = [];
        } else {
            Qt.callLater(next);
        }
    }
    onNotifUpChanged: notifUp ? done() : Qt.callLater(next)
    onEnabledChanged: if (!enabled) { queue = []; done(); }

    // Click on the card.
    function activate(m) {
        if (!m)
            return;
        switch (m.kind) {
        case "charging":
            ControlState.toggle("main");
            break;
        case "bluetooth":
            ControlState.toggle("bluetooth");
            break;
        case "wifi":
            ControlState.toggle("wifi");
            break;
        case "screenshot":
            if (m.file && !Screenshot.dryRun)
                Quickshell.execDetached(["xdg-open", m.file]);
            else if (m.file)
                console.log("activities (dry run): open", m.file);
            break;
        case "copy":
            if (!m.ocr)
                ClipboardState.toggle();
            break;
        }
        done();
    }

    // ---- What a moment shows -----------------------------------------------------------------
    // { icon, badge ("primary" | "secondary" | "tertiary" | "plain"), title,
    //   detail, value, gauge (0-1, or -1 = none), image (url), swatch (color) }.
    // Read live, so a battery time or a headset's level that arrives while
    // it shows is filled in.
    function duration(s) {
        const h = Math.floor(s / 3600);
        const m = Math.round((s % 3600) / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }

    function view(m) {
        if (!m)
            return null;
        const v = { icon: "info", badge: "secondary", title: "", detail: "", value: "", gauge: -1, image: "", swatch: "" };
        switch (m.kind) {
        case "charging": {
            const d = UPower.displayDevice;
            const pct = BatteryCare.fake ? BatteryCare.percent : Math.round((d?.percentage ?? 0) * 100);
            v.value = pct + "%";
            v.gauge = pct / 100;
            if (m.plugged) {
                v.icon = "bolt";
                v.badge = "primary";
                v.title = "Charging";
                const s = d?.timeToFull ?? 0;
                v.detail = s > 0 ? duration(s) + " to full" : "";
            } else {
                v.icon = "power_off";
                v.badge = "plain";
                v.title = "On battery";
                const s = d?.timeToEmpty ?? 0;
                const saver = PowerProfiles.profile === PowerProfile.PowerSaver;
                v.detail = [saver ? "Power saver" : "", s > 0 ? duration(s) + " left" : ""].filter(x => x !== "").join(" · ");
            }
            break;
        }
        case "bluetooth": {
            const dev = m.device ?? null;
            v.icon = Peripherals.glyphFor(dev?.icon ?? m.glyph ?? "headphones");
            v.badge = m.connected ? "secondary" : "plain";
            v.title = dev ? (dev.name || dev.deviceName || m.name) : m.name;
            v.detail = m.connected ? "Connected" : "Disconnected";
            v.value = m.connected ? (dev ? Peripherals.levelOf(dev) : (m.level ?? "")) : "";
            break;
        }
        case "screenshot":
            v.icon = "screenshot_region";
            v.badge = "tertiary";
            v.title = "Screenshot saved";
            v.detail = "Copied · click to open";
            v.image = m.file ? "file://" + m.file : "";
            break;
        case "copy": {
            const hidden = Privacy.sharing || Recorder.recording;
            if (m.swatch) {
                v.icon = "colorize";
                v.swatch = m.swatch;
                v.title = "Copied";
                v.detail = m.swatch + (m.rgb ? " · " + m.rgb : "");
            } else if (m.ocr) {
                v.icon = m.words > 0 ? "text_fields" : "search_off";
                v.badge = m.words > 0 ? "tertiary" : "plain";
                v.title = m.words > 0 ? "Copied " + m.words + (m.words === 1 ? " word" : " words") : "No text found";
                v.detail = m.words > 0 ? (hidden ? "" : m.text) : "in that part of the screen";
            } else if (m.image) {
                v.icon = "image";
                v.badge = "tertiary";
                v.title = "Copied a picture";
                v.detail = m.imageInfo ?? "";
                v.image = hidden ? "" : (m.thumb ?? "");
            } else {
                v.icon = "content_copy";
                v.badge = "tertiary";
                v.title = "Copied";
                v.detail = hidden ? "" : m.text;
            }
            break;
        }
        case "wifi":
            v.icon = m.connected ? "wifi" : "wifi_off";
            v.badge = m.connected ? "secondary" : "plain";
            v.title = m.connected ? "Connected" : "Disconnected";
            v.detail = m.ssid ?? "";
            break;
        case "focus":
            v.icon = m.work ? "target" : "coffee";
            v.badge = m.work ? "primary" : "tertiary";
            v.title = m.title ?? "";
            v.detail = m.detail ?? "";
            break;
        }
        return v;
    }

    // ---- Charger ---------------------------------------------------------------------------------
    // When it was last plugged in or out: the power mode BatteryCare switches
    // with it is said by the same moment, not by the OSD too.
    property real plugAt: 0
    Connections {
        target: BatteryCare
        function onUnpluggedChanged() {
            if (!BatteryCare.hasBattery)
                return;
            root.plugAt = Date.now();
            root.show({ kind: "charging", plugged: !BatteryCare.unplugged });
        }
    }
    // OsdState asks before showing the power mode.
    function swallowsPower() {
        return enabled && Style.activityCharging && Date.now() - plugAt < 4000;
    }

    // ---- Bluetooth headphones and speakers ---------------------------------------------------------
    function isAudio(dev) {
        const icon = String(dev?.icon ?? "").toLowerCase();
        return icon.includes("audio") || icon.includes("headset") || icon.includes("headphone") || icon.includes("speaker");
    }
    Instantiator {
        model: Bluetooth.devices
        delegate: QtObject {
            required property var modelData
            readonly property bool connected: modelData?.connected ?? false
            onConnectedChanged: root.btChanged(modelData, connected)
        }
    }
    function btChanged(dev, connected) {
        if (!armed || !isAudio(dev))
            return;
        if (connected) {
            show({ kind: "bluetooth", device: dev, connected: true, name: dev.name || dev.deviceName || "" });
        } else {
            // Gone because Bluetooth was turned off: the OSD says that.
            btGone.dev = dev;
            btGone.name = dev.name || dev.deviceName || "";
            btGone.restart();
        }
    }
    Timer {
        id: btGone
        property var dev: null
        property string name: ""
        interval: 700
        onTriggered: {
            if (Bluetooth.defaultAdapter?.enabled ?? false)
                root.show({ kind: "bluetooth", device: null, connected: false, name: name, glyph: dev?.icon ?? "headphones" });
        }
    }

    // ---- Wi-Fi -------------------------------------------------------------------------------------
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property string ssid: wifiDevice?.networks.values.find(n => n.connected)?.name ?? ""
    property string lastSsid: ""
    onSsidChanged: {
        const before = lastSsid;
        lastSsid = ssid;
        if (!armed)
            return;
        if (ssid !== "") {
            wifiGone.stop();
            if (ssid !== before)
                show({ kind: "wifi", connected: true, ssid: ssid });
        } else if (before !== "") {
            // Wait: turning Wi-Fi off (the OSD's) or moving to another network.
            wifiGone.ssid = before;
            wifiGone.restart();
        }
    }
    Timer {
        id: wifiGone
        property string ssid: ""
        interval: 900
        onTriggered: {
            if (Networking.wifiEnabled && root.ssid === "")
                root.show({ kind: "wifi", connected: false, ssid: ssid });
        }
    }

    // ---- Screenshots, picked colors, text from the screen --------------------------------------
    // Screenshot.finish / ColorPicker.got / Screenshot.gotText call these
    // and copy to the clipboard themselves: that copy isn't news again.
    function screenshot(file) {
        expectCopy();
        return show({ kind: "screenshot", file: file });
    }
    function color(hex, rgb) {
        expectCopy();
        return show({ kind: "copy", swatch: hex, rgb: rgb });
    }
    function textRead(text, words) {
        expectCopy();
        const first = text.split("\n")[0].trim();
        return show({ kind: "copy", ocr: true, words: words, text: first.length > 90 ? first.substring(0, 89) + "…" : first });
    }

    // ---- Copies --------------------------------------------------------------------------------------
    // cliphist's database changes when something is stored (clip-store.sh
    // leaves secrets out, so they never come here). Then its newest entry is
    // read. The same text stored again (wl-clip-persist hands it over when
    // an app closes, or the history pastes an old one) isn't a new copy.
    property real expectUntil: 0
    function expectCopy() {
        expectUntil = Date.now() + 2500;
    }
    readonly property bool watchCopies: enabled && Style.activityClipboard && !Clipboard.dryRun
    readonly property string clipDb: Quickshell.env("CLIPHIST_DB_PATH")
        || ((Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/cliphist/db")
    property string topId: ""
    property string topText: ""
    property bool topKnown: false

    // Watched only once it exists (cliphist makes it with the first copy):
    // until then, looked for every few seconds.
    property bool dbThere: false
    FileView {
        path: root.watchCopies && root.dbThere ? root.clipDb : ""
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: clipSettle.restart()
    }
    Process {
        id: dbCheck
        command: ["test", "-e", root.clipDb]
        onExited: code => {
            root.dbThere = code === 0;
            if (root.dbThere)
                root.readTop();
        }
    }
    Timer {
        running: root.watchCopies && !root.dbThere
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: dbCheck.running = true
    }
    onWatchCopiesChanged: if (watchCopies && dbThere) readTop()
    Timer {
        id: clipSettle
        interval: 150
        onTriggered: root.readTop()
    }
    function readTop() {
        if (!top.running)
            top.running = true;
    }
    Process {
        id: top
        command: ["sh", "-c", "cliphist list 2>/dev/null | head -n 1"]
        stdout: StdioCollector {
            onStreamFinished: root.gotTop(text.replace(/\n$/, ""))
        }
    }
    function gotTop(line) {
        const tab = line.indexOf("\t");
        if (tab < 0)
            return;
        const id = line.slice(0, tab);
        const preview = line.slice(tab + 1);
        const first = !topKnown;
        const same = preview === topText;
        const newer = Number(id) > Number(topId);
        topKnown = true;
        topId = id;
        topText = preview;
        if (first || same || !newer || Date.now() < expectUntil || !armed)
            return;
        const img = /^\[\[ binary data .* (\w+) (\d+x\d+) \]\]$/.exec(preview);
        if (img) {
            const entry = { id: id, imageInfo: img[1] + " " + img[2] };
            const thumb = Clipboard.thumbFor(entry);
            show({ kind: "copy", image: true, id: id, imageInfo: img[1] + " " + img[2], thumb: "" });
            decode.thumb = thumb;
            decode.command = ["sh", "-c", 'mkdir -p "$(dirname "$2")"; [ -s "$2" ] || cliphist decode "$1" > "$2"', "decode", id, thumb];
            decode.running = true;
            return;
        }
        const text = preview.replace(/\s+/g, " ").trim();
        // A color, as text: a swatch of it.
        const hex = /^#?([0-9a-fA-F]{6})$/.exec(text);
        if (hex)
            show({ kind: "copy", swatch: "#" + hex[1].toLowerCase() });
        else
            show({ kind: "copy", text: text.length > 80 ? text.substring(0, 79) + "…" : text });
    }
    Process {
        id: decode
        property string thumb: ""
        onExited: {
            if (root.moment?.kind === "copy" && root.moment.image) {
                root.moment = Object.assign({}, root.moment, { thumb: "file://" + thumb });
                root.revision++;
            }
        }
    }

    // ---- The bubble ------------------------------------------------------------------------------------
    readonly property bool bubbleOn: enabled && Style.activityBubble
    readonly property bool showRecording: bubbleOn && (Recorder.recording || previewing.recording)
    readonly property bool showTimer: bubbleOn && (FocusTimer.active || previewing.timer)
    readonly property bool showAgents: bubbleOn && Style.activityAgents
        && (Agents.workingCount + Agents.waitingCount > 0 || previewing.agents)
    readonly property bool bubbleShown: showRecording || showTimer || showAgents

    // The bubble keeps Agents counting, even with its notifications off.
    readonly property bool wantsAgents: bubbleOn && Style.activityAgents
    property bool agentsUsed: false
    onWantsAgentsChanged: useAgents()
    function useAgents() {
        if (wantsAgents !== agentsUsed) {
            Agents.use(wantsAgents);
            agentsUsed = wantsAgents;
        }
    }

    Component.onCompleted: {
        lastSsid = ssid;
        useAgents();
    }

    // ---- Previews (IPC) ---------------------------------------------------------------------------------
    property var previewing: ({ recording: false, timer: false, agents: false })
    // Fake numbers for a previewed bubble.
    property real previewStarted: 0
    Timer {
        id: previewEnd
        interval: 8000
        onTriggered: root.previewing = ({ recording: false, timer: false, agents: false })
    }

    function preview(kind) {
        switch (kind) {
        case "charging": return show({ kind: "charging", plugged: true, preview: true });
        case "unplugged": return show({ kind: "charging", plugged: false, preview: true });
        case "bluetooth": return show({ kind: "bluetooth", connected: true, name: "Headphones", level: "80%", glyph: "audio-headset", preview: true });
        case "screenshot": return show({ kind: "screenshot", file: Quickshell.env("MINE_ACTIVITY_PICTURE") || "", preview: true });
        case "copy": return show({ kind: "copy", text: "the text you just copied, cut short when it is long", preview: true });
        case "picture": return show({ kind: "copy", image: true, imageInfo: "png 896x515", thumb: Quickshell.env("MINE_ACTIVITY_PICTURE") ? "file://" + Quickshell.env("MINE_ACTIVITY_PICTURE") : "", preview: true });
        case "color": return show({ kind: "copy", swatch: "#d0bcff", rgb: "rgb(208, 188, 255)", preview: true });
        case "ocr": return show({ kind: "copy", ocr: true, words: 12, text: "Text read off the screen, first line", preview: true });
        case "wifi": return show({ kind: "wifi", connected: true, ssid: "Home Wi-Fi", preview: true });
        case "wifioff": return show({ kind: "wifi", connected: false, ssid: "Home Wi-Fi", preview: true });
        case "focus": return show({ kind: "focus", work: false, title: "Break time", detail: "5 minutes · round 2 done", preview: true });
        case "recording":
        case "timer":
        case "agents": {
            const p = Object.assign({}, previewing);
            p[kind] = true;
            previewing = p;
            previewStarted = Date.now();
            previewEnd.restart();
            return true;
        }
        }
        return false;
    }
}
