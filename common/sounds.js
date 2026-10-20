.pragma library

// Which file each UI sound plays (services/Sounds.qml for the shell,
// lock.qml for locking). Short, soft ones from the sound themes installed
// on the system; change a path here to use another sound (.oga, .ogg, .wav).
// The first one that exists is used.
const fd = "/usr/share/sounds/freedesktop/stereo/";
const ocean = "/usr/share/sounds/ocean/stereo/";

const files = {
    volume: [fd + "audio-volume-change.oga"],              // a 70 ms click, like a Mac's
    screenshot: [fd + "camera-shutter.oga"],
    recordStart: [fd + "device-added.oga", ocean + "button-pressed.oga"],
    recordStop: [fd + "device-removed.oga", ocean + "button-pressed.oga"],
    lock: [ocean + "service-logout.oga", fd + "service-logout.oga"],
    unlock: [ocean + "completion-success.oga", fd + "complete.oga"],
    plug: [fd + "power-plug.oga", ocean + "power-plug.oga"],
    unplug: [fd + "power-unplug.oga", ocean + "power-unplug.oga"],
    agentDone: [fd + "complete.oga", ocean + "completion-success.oga"],    // a Claude Code session is done (services/Agents.qml)
    deviceOn: [fd + "device-added.oga"],
    deviceOff: [fd + "device-removed.oga"]
};

// The command that plays `name` at `volume` (0-1), or [] if unknown. pw-play
// picks the first file that exists itself (sh -c), so nothing is read here.
function command(name, volume) {
    const list = files[name];
    if (!list)
        return [];
    const v = Math.max(0, Math.min(1, volume)).toFixed(2);
    return ["sh", "-c", 'for f in "$@"; do [ -e "$f" ] && exec pw-play --volume ' + v + ' "$f"; done', "sh"].concat(list);
}
