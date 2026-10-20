import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.common
import qs.services

// Speaker volume. Click: the volume popup right under it (Style.volumePopup;
// off = click mutes), middle click: mute, right click: the control
// center's sound devices. Scroll: up/down, the OSD shows under the icon.
Clickable {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    tip: sink ? (sink.description || sink.nickname || sink.name) : "No sound output"
    tipDetail: !sink ? "" : (muted ? "Muted" : Math.round(volume * 100) + "%") + " · right-click: sound devices"

    // Without this the sink's volume and mute stay empty.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    // This icon on its screen: x from the bar window, which spans the screen.
    function iconRect() {
        const win = root.QsWindow.window;
        return win ? win.itemRect(root) : Qt.rect(0, 0, width, height);
    }
    function screenName() {
        return root.QsWindow.window?.screen?.name ?? "";
    }

    function route(button) {
        if (button === Qt.RightButton)
            ControlState.toggle("audio");
        else if (button === Qt.LeftButton && Style.volumePopup)
            VolumeState.toggle(screenName(), iconRect());
        else
            ControlState.toggleMute(sink);
    }
    onClicked: mouse => route(mouse.button)
    // One mouse notch = volumeStep; touchpads move it smoothly.
    onWheel: wheel => {
        if (!sink?.audio)
            return;
        const r = iconRect();
        OsdState.anchorTo(screenName(), r.x + r.width / 2);
        const delta = (wheel.angleDelta.y || -wheel.angleDelta.x) / 120;
        sink.audio.volume = Math.max(0, Math.min(1, volume + delta * Style.volumeStep));
        if (sink.audio.muted && delta > 0)
            sink.audio.muted = false;
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: root.muted || root.volume === 0 ? "volume_off"
            : root.volume < 0.34 ? "volume_mute"
            : root.volume < 0.67 ? "volume_down"
            : "volume_up"
        fill: root.muted ? 0 : 1
        opacity: root.muted ? 0.6 : 1
    }

    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.volume * 100) + "%"
        font.features: ({ "tnum": 1 })
        color: root.muted ? Colors.textOnSurfaceVariant : Colors.textOnSurface
    }
}
