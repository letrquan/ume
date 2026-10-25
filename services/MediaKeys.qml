pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.common

// What the media keys do (volume, mic, brightness, play/pause...). mango
// runs `mine key <action>`, which calls these through the "keys" IPC target
// (and falls back to Noctalia when the shell isn't running). The OSD pops up
// for each press, also at 100%.
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    // The player the whole shell shows (common/Players.qml).
    readonly property var player: Players.active

    function volume(step) {
        if (!sink?.audio)
            return;
        if (step > 0 && sink.audio.muted)
            sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + step));
        OsdState.show("volume");
    }
    function toggleMute() {
        if (!sink?.audio)
            return;
        sink.audio.muted = !sink.audio.muted;
        OsdState.show("volume");
    }
    function toggleMic() {
        if (!source?.audio)
            return;
        source.audio.muted = !source.audio.muted;
        OsdState.show("mic");
    }
    function brightness(step) {
        if (!Brightness.ready)
            return;
        // Yours: auto brightness stops gliding and learns it.
        AutoBrightness.userSet();
        Brightness.set(Math.max(0.01, Math.min(1, Brightness.value + step)));
        OsdState.show("brightness");
    }

    PwObjectTracker {
        objects: [root.sink, root.source].filter(node => node !== null)
    }
}
