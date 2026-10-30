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
    deviceOff: [fd + "device-removed.oga"],
    alarm: [ocean + "alarm-clock-elapsed.oga", fd + "alarm-clock-elapsed.oga"]    // a timer or an alarm (services/Timers.qml), over and over
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

// The same, over and over until the process is stopped (SIGTERM ends the
// sound playing right then, not only the loop), a short pause between. It
// also ends by itself after `seconds`, so a ring can't outlive a shell that
// crashed or was stopped while it rang.
function loopCommand(name, volume, seconds) {
    const list = files[name];
    if (!list)
        return [];
    const v = Math.max(0, Math.min(1, volume)).toFixed(2);
    const s = Math.max(1, Math.round(Number(seconds) || 60));
    return ["sh", "-c", 'trap \'kill $p 2>/dev/null; exit 0\' TERM INT; end=$(( $(date +%s) + ' + s + ' )); '
            + 'for f in "$@"; do [ -e "$f" ] && break; done; [ -e "$f" ] || exit 1; '
            + 'while [ "$(date +%s)" -lt "$end" ]; do pw-play --volume ' + v + ' "$f" & p=$!; wait $p; sleep 0.7; done', "sh"].concat(list);
}
