.pragma library

// What the privacy dots (services/Privacy.qml) read out of Pipewire's links
// and out of the /proc scan for the camera. Plain functions on plain
// objects, so they can be tested without Pipewire (node, after dropping the
// first line).
//
// A link: { state: "active" | "paused" | "other", source: node, target: node }
// A node: { id, name, isSink, isStream, audio (it carries sound), video (a
//           video source), app (who it belongs to, "" when unknown) }

// A camera seen by Pipewire itself (the v4l2 / libcamera nodes), as opposed
// to a screen cast (xdg-desktop-portal-wlr's stream, OBS's virtual sources…).
function isCamera(node) {
    return /^(v4l2_|libcamera_)/.test(node.name || "");
}

// A microphone (or another sound input: a headset, a virtual source), not
// a speaker. Recording what a speaker plays (cava, the screen recorder's
// sound, "Monitor of …") takes its sound from the speaker's own node, so it
// never comes from one of these.
function isMic(node) {
    return node.audio && !node.isSink && !node.isStream && !/\.monitor$/.test(node.name || "");
}

// The links that matter, by kind:
//   mic:    an app records from a microphone, and the sound is flowing
//           (a paused link: the app stopped listening for now)
//   share:  an app takes a picture stream that isn't a camera: the screen
//   camera: an app takes the camera through Pipewire (only to put names
//           on the camera dot; whether it's on comes from the /proc scan)
// Each list holds the targets (the apps), once each.
function classify(links) {
    const out = { mic: [], share: [], camera: [] };
    const seen = { mic: {}, share: {}, camera: {} };
    function add(kind, node) {
        if (seen[kind][node.id])
            return;
        seen[kind][node.id] = true;
        out[kind].push(node);
    }
    for (const l of links || []) {
        const s = l.source, t = l.target;
        if (!s || !t)
            continue;
        if (isMic(s)) {
            if (t.isStream && l.state === "active")
                add("mic", t);
        } else if (s.video) {
            if (l.state !== "active" && l.state !== "paused")
                continue;
            add(isCamera(s) ? "camera" : "share", t);
        }
    }
    return out;
}

// App names for the hover text, each once, in order.
function names(nodes) {
    const out = [];
    for (const n of nodes) {
        const name = n.app || n.name || "";
        if (name !== "" && !out.includes(name))
            out.push(name);
    }
    return out;
}

// The /proc scan's output: one "pid<TAB>name" line per process that has a
// /dev/video* open. Anything else is skipped.
function holders(text) {
    const out = [];
    for (const line of (text || "").split("\n")) {
        const m = /^(\d+)\t(.*)$/.exec(line);
        if (m)
            out.push({ pid: Number(m[1]), comm: m[2].trim() });
    }
    return out;
}
