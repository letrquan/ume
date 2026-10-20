pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Apps playing sound right now (Pipewire playback streams), for the volume
// per app in the control center. Changing volume or mute goes through
// ControlState.setVolume / toggleMute like the other sliders (so
// MINE_CC_DRYRUN=1 only prints it).
Singleton {
    id: root

    // The control center's app list is open (remembered while the shell runs).
    property bool expanded: false

    // Playback streams: Quickshell counts them as sinks (they take the app's
    // sound in); recording streams, cava's included, are not. The speaker
    // EQ's own stream isn't an app.
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink && n.audio && !ControlState.isSpeakerEq(n))

    // Desktop entries load a moment after start; icon bindings read this so
    // they look again once they're there.
    readonly property int appsLoaded: DesktopEntries.applications.values.length

    function props(node) {
        return node?.properties ?? {};
    }
    function name(node) {
        const p = props(node);
        return p["application.name"] || node?.description || node?.nickname || node?.name || "App";
    }
    // What it's playing (a tab, a song), when the app says something useful.
    function detail(node) {
        const m = props(node)["media.name"] ?? "";
        return m === name(node) || m === "AudioStream" || m === "Playback" ? "" : m;
    }
    function entry(node) {
        const p = props(node);
        for (const key of [p["application.id"], p["pipewire.access.portal.app_id"], p["application.process.binary"], p["application.name"]]) {
            if (!key)
                continue;
            const e = DesktopEntries.byId(key) ?? DesktopEntries.heuristicLookup(key);
            if (e)
                return e;
        }
        return null;
    }
    function icon(node) {
        const icon = props(node)["application.icon-name"] || entry(node)?.icon || "audio-x-generic";
        if (icon.startsWith("/"))
            return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }
}
