pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.common
import "privacy.js" as Find

// Who's listening or watching, for the bar's privacy dots
// (bar/PrivacyItem.qml, "Privacy dots" in Bar items), and so new
// notifications stay quiet while the screen is shared (`quiet`, read by
// Notifs).
//  - Microphone: an app records from a microphone and the sound flows
//    (Pipewire: a mic node linked to an app's recording stream). The music
//    visualizer (cava) and anything else recording what the speakers play
//    take that from the speaker's own node, so they never count.
//  - Screen: an app takes a screen cast (the portal's Pipewire stream:
//    Discord, OBS, a browser sharing a screen). The shell's own recorder
//    (wf-recorder) doesn't go through Pipewire; it has its red dot.
//  - Camera: only when a process really has a /dev/video* open (an app
//    merely ready to use it, or the camera waking up for the presence
//    sensor, doesn't count). Looked for only when the camera streams.
//
// Cost: the Pipewire part is bindings on links Quickshell tracks anyway;
// only links from a mic or a picture stream get bound (for their state),
// with the apps at their other end (for their names). The camera, only
// while a privacy item is on the bar: two or three tiny sysfs reads every
// Style.privacyCameraPoll ms (the camera's USB power state and its
// streaming interfaces' setting; reading them doesn't wake it), and a /proc
// scan (~60 ms of CPU) when it starts streaming, then every 30 s while it
// does.
//
// Tests: MINE_PRIVACY_FAKE = a JSON file of links (as privacy.js takes them)
// instead of Pipewire's; MINE_PRIVACY_SYS = a fake /sys, MINE_PRIVACY_PROC =
// a fake /proc.
Singleton {
    id: root

    // ---- Microphone and screen: Pipewire's links ---------------------------------------
    readonly property string fakePath: Quickshell.env("MINE_PRIVACY_FAKE") ?? ""
    readonly property bool faking: fakePath !== ""
    property var fakeLinks: []

    function plainNode(n) {
        if (!n)
            return null;
        return {
            id: n.id,
            name: n.name ?? "",
            isSink: n.isSink,
            isStream: n.isStream,
            audio: !!n.audio,
            video: n.type === PwNodeType.VideoSource,
            // Only once bound (the tracker below), for the hover text.
            app: n.properties?.["application.name"] || n.description || "",
            node: n
        };
    }
    function stateName(s) {
        return s === PwLinkState.Active ? "active" : s === PwLinkState.Paused ? "paused" : "other";
    }

    // The links that could matter: from a microphone, or a picture stream.
    // Quickshell only knows a link's state (sound flowing or not) once it's
    // bound (the tracker below), so only these few get bound. Only what's
    // known without binding is read here, so binding doesn't change the list.
    readonly property var candidates: faking ? [] : Pipewire.linkGroups.values.filter(g => g.source && g.target
        && (g.source.type === PwNodeType.VideoSource || Find.isMic({
            audio: !!g.source.audio, isSink: g.source.isSink, isStream: g.source.isStream, name: g.source.name ?? ""
        })))
    // (A node going away can leave its links without it for a moment.)
    readonly property var links: faking ? fakeLinks : candidates.filter(g => g.source && g.target).map(g => ({
        state: stateName(g.state), source: plainNode(g.source), target: plainNode(g.target)
    }))
    readonly property var found: Find.classify(links)

    readonly property bool micOn: found.mic.length > 0
    readonly property var micApps: Find.names(found.mic)
    readonly property var mic: Pipewire.defaultAudioSource
    readonly property bool micMuted: mic?.audio?.muted ?? false
    readonly property bool sharing: found.share.length > 0
    readonly property var shareApps: Find.names(found.share)

    // New notifications go quietly to the list while the screen is shared
    // or recorded (Style.privacyQuietSharing).
    readonly property bool quiet: Style.privacyQuietSharing && (sharing || Recorder.recording)

    // The orange dot's click (MINE_CC_DRYRUN=1 only prints it).
    function toggleMute() {
        ControlState.toggleMute(mic);
    }

    // Bound: those links (for their state), the apps at their other end (for
    // their names) and the mic (for its mute state).
    PwObjectTracker {
        objects: root.candidates.concat(root.candidates.map(g => g.target), [root.mic]).filter(n => n)
    }

    FileView {
        path: root.fakePath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.fakeLinks = JSON.parse(text());
            } catch (e) {
                root.fakeLinks = [];
            }
        }
    }

    // ---- Camera ------------------------------------------------------------------------------
    // Privacy items on the bar right now (bar/PrivacyItem.qml counts itself
    // in); the camera is only watched while there's one.
    property int users: 0
    function use(delta) {
        users = Math.max(0, users + delta);
    }
    readonly property bool watchCamera: Style.privacyCamera && users > 0

    readonly property string sysDir: Quickshell.env("MINE_PRIVACY_SYS") || "/sys"
    readonly property string procDir: Quickshell.env("MINE_PRIVACY_PROC") || "/proc"

    // Processes with a /dev/video* open: [{ pid, comm }], while it streams.
    property var holders: []
    readonly property bool cameraOn: watchCamera && holders.length > 0
    readonly property var cameraApps: {
        void appsLoaded;
        const out = [];
        for (const h of holders) {
            // Through Pipewire: the apps taking its camera stream.
            const viaPipewire = h.comm === "pipewire" || h.comm === "wireplumber";
            const list = viaPipewire ? Find.names(found.camera) : [appName(h.comm)];
            for (const n of (list.length > 0 ? list : ["PipeWire"]))
                if (!out.includes(n))
                    out.push(n);
        }
        return out;
    }
    // "brave" -> its desktop entry's name, else "Brave".
    function appName(comm) {
        if (comm === "")
            return "An app";
        const e = DesktopEntries.byId(comm) ?? DesktopEntries.heuristicLookup(comm);
        return e?.name || comm.charAt(0).toUpperCase() + comm.slice(1);
    }
    // Desktop entries load a moment after start; the names are looked up
    // again once they're there.
    readonly property int appsLoaded: DesktopEntries.applications.values.length

    // The camera devices, found once: for each, the USB device's power state
    // ("status"), and its video streaming interfaces' alternate setting
    // ("alt": an isochronous camera uses a setting other than 0 only while it
    // streams). A camera whose streaming can't be seen that way ("bulk", or
    // no USB power state at all) counts as streaming whenever it's awake
    // twice in a row (the presence sensor wakes it for ~2 s at a time).
    property var camFiles: []           // [{ path, kind: "status" | "alt" }]
    property bool camBulk: false
    property bool camFound: false

    Process {
        running: root.watchCamera && !root.camFound
        command: ["sh", "-c", `
            for v in "$1"/class/video4linux/video*; do
                [ -e "$v/device" ] || continue
                d=$(readlink -f "$v/device")
                while [ -n "$d" ] && [ "$d" != / ] && [ ! -e "$d/power/runtime_status" ]; do d=\${d%/*}; done
                [ -e "$d/power/runtime_status" ] || { echo bulk; continue; }
                echo "status $d/power/runtime_status"
                for i in "$d"/*:*; do
                    [ "$(cat "$i/bInterfaceClass" 2>/dev/null)" = 0e ] || continue
                    [ "$(cat "$i/bInterfaceSubClass" 2>/dev/null)" = 02 ] || continue
                    alt=$(cat "$i/bAlternateSetting" 2>/dev/null | tr -d ' ')
                    if [ "$alt" != 0 ] || [ "$(cat "$i/bNumEndpoints" 2>/dev/null)" = 00 ]; then
                        echo "alt $i/bAlternateSetting"
                    else
                        echo bulk
                    fi
                done
            done | sort -u`, "sh", root.sysDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const files = [];
                let bulk = false;
                for (const line of text.split("\n")) {
                    const m = /^(status|alt) (.+)$/.exec(line);
                    if (m)
                        files.push({ path: m[2], kind: m[1] });
                    else if (line === "bulk")
                        bulk = true;
                }
                root.camBulk = bulk;
                root.camFiles = files;
                root.camFound = true;
            }
        }
    }

    Instantiator {
        id: camReaders
        model: root.camFiles
        delegate: FileView {
            required property var modelData
            path: modelData.path
            printErrors: false
            blockAllReads: true     // sysfs: tiny, read right away
        }
    }

    // Streaming now (from the last poll), and polls in a row it's been awake.
    property bool camStreaming: false
    property int awakeRuns: 0

    function poll() {
        let awake = false, altOn = false, statuses = 0;
        for (let i = 0; i < camReaders.count; i++) {
            const f = camReaders.objectAt(i);
            f.reload();
            const value = f.text().trim();
            if (f.modelData.kind === "status") {
                statuses++;
                awake = awake || value === "active";
            } else if (value !== "" && value !== "0") {
                altOn = true;
            }
        }
        if (statuses === 0)
            awake = true;       // no power state to go by: a slow scan
        awakeRuns = awake ? awakeRuns + 1 : 0;
        const hasAlt = root.camFiles.some(f => f.kind === "alt");
        camStreaming = awake && (altOn || ((root.camBulk || !hasAlt) && awakeRuns >= 2));
    }

    Timer {
        running: root.watchCamera && root.camFound && (root.camFiles.length > 0 || root.camBulk)
        interval: Math.max(500, Style.privacyCameraPoll)
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    onWatchCameraChanged: if (!watchCamera) {
        camStreaming = false;
        awakeRuns = 0;
    }
    onCamStreamingChanged: {
        if (camStreaming)
            scan.running = true;
        else
            holders = [];
    }

    // Who has a /dev/video* open: own processes only (others' fds can't be
    // read). Names from /proc/<pid>/comm.
    Process {
        id: scan
        command: ["sh", "-c", `
            find "$1"/[0-9]*/fd -maxdepth 1 -lname '/dev/video*' 2>/dev/null | sed 's|/fd/[^/]*$||' | sort -u |
            while read -r d; do printf '%s\\t%s\\n' "\${d##*/}" "$(cat "$d/comm" 2>/dev/null)"; done`,
            "sh", root.procDir]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.camStreaming)
                    root.holders = Find.holders(text);
            }
        }
    }
    Timer {
        running: root.camStreaming
        interval: 30000
        repeat: true
        onTriggered: scan.running = true
    }
}
