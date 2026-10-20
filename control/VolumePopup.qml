import QtQuick
import Quickshell.Services.Pipewire
import qs.common
import qs.services

// The volume popup's card, laid out like the macOS Sound menu: "Sound" and
// the %, one slim slider, the outputs (✓ on the one in use, click to
// switch), the mic, a slider per app playing sound, and "Sound settings…".
// It grows out of the bar's speaker icon, sits right under it (kept inside
// the screen) and shrinks back into the icon when it closes.
// Everything changes through ControlState (MINE_CC_DRYRUN=1 only prints).
Item {
    id: root

    // The icon it grows out of, in this item's (the screen's) coordinates.
    property rect from: Qt.rect(0, 0, 0, 0)
    property bool open: false

    // Back in the icon and hidden: the window can go now.
    readonly property bool settled: !open && t === 0

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    // Apps playing sound (tests can hand in fakes).
    property var streams: AppAudio.streams

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    // ---- Where the card goes ----------------------------------------------------------------
    readonly property real toWidth: Style.volumePopupWidth
    readonly property real toX: Math.max(Style.marginEdge,
        Math.min(width - toWidth - Style.marginEdge, from.x + from.width / 2 - toWidth / 2))
    readonly property real toY: Style.marginEdge + Style.islandHeight + Style.osdGap
    // The card's height eases on its own, so apps coming and going glide.
    property real toHeight: content.implicitHeight + 2 * pad
    Behavior on toHeight {
        NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
    }
    readonly property int pad: 12

    // 0 = the icon, 1 = the card.
    property real t: 0
    onOpenChanged: {
        morph.stop();
        morph.to = open ? 1 : 0;
        morph.duration = open ? Motion.morphIn : Motion.morphOut;
        morph.start();
    }
    NumberAnimation {
        id: morph
        target: root
        property: "t"
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasized
    }

    function lerp(a, b) {
        return a + (b - a) * t;
    }

    // Volume and mute only fill in for tracked nodes.
    PwObjectTracker {
        objects: [root.sink, root.source].filter(n => n !== null).concat(AppAudio.streams)
    }

    // A click on the card itself must not reach the window's "outside" catcher.
    MouseArea {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        acceptedButtons: Qt.AllButtons
    }

    Item {
        id: card

        x: root.lerp(root.from.x, root.toX)
        y: root.lerp(root.from.y, root.toY)
        width: root.lerp(root.from.width, root.toWidth)
        height: root.lerp(root.from.height, root.toHeight)
        // Fades in over the first bit, so it doesn't start as a solid pill
        // over the icon.
        opacity: Math.min(1, root.t * 5)
        visible: root.t > 0

        Glass {
            anchors.fill: parent
            radius: root.lerp(root.from.height / 2, Style.volumePopupRadius)
            color: Style.alpha(Colors.surfaceContainer, root.lerp(Style.islandOpacity, Style.ccOpacity))
        }

        // The content: clipped to the card, slides in near the end of the
        // opening and leaves first when closing (like MorphCard).
        Item {
            anchors.fill: parent
            clip: true
            readonly property bool revealed: root.open && root.t > 0.6
            opacity: revealed ? 1 : 0
            transform: Translate {
                y: parent.revealed ? 0 : 6
                Behavior on y {
                    NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: parent.revealed ? Motion.contentIn : Motion.contentOut
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: parent.revealed ? Motion.emphasizedDecel : Motion.emphasizedAccel
                }
            }

            Column {
                id: content
                x: root.pad
                y: root.pad
                width: root.toWidth - 2 * root.pad

                // ---- Sound                                        66% ----
                Item {
                    width: parent.width
                    height: 26

                    StyledText {
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Sound"
                        role: "title"
                    }
                    StyledText {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.muted ? "Muted" : Math.round(root.volume * 100) + "%"
                        font.features: ({ "tnum": 1 })
                        color: Colors.textOnSurfaceVariant
                    }
                }

                // 🔈 ━━━━━━━●──── 🔊   (the small speaker mutes)
                Item {
                    width: parent.width
                    height: 34

                    SoftIcon {
                        id: quiet
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.muted ? "volume_off" : "volume_mute"
                        clickable: true
                        onClicked: ControlState.toggleMute(root.sink)
                    }
                    SlimSlider {
                        anchors.left: quiet.right
                        anchors.right: loud.left
                        anchors.leftMargin: 2
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.volume
                        muted: root.muted
                        onMoved: v => ControlState.setVolume(root.sink, v)
                    }
                    SoftIcon {
                        id: loud
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        name: "volume_up"
                    }
                }

                // ---- Output -------------------------------------------------------------
                SectionLabel { text: "Output" }
                Repeater {
                    model: ControlState.sinks

                    MenuRow {
                        required property var modelData
                        width: content.width
                        label: ControlState.nodeName(modelData)
                        checked: modelData === root.sink
                        onClicked: ControlState.useSink(modelData)
                    }
                }

                // ---- Input: the mic level, and its devices when there's a choice --------
                SectionLabel {
                    visible: Style.volumePopupInput && root.source !== null
                    text: "Input"
                }
                Item {
                    visible: Style.volumePopupInput && root.source !== null
                    width: parent.width
                    height: 34

                    SoftIcon {
                        id: micIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.source?.audio?.muted ? "mic_off" : "mic"
                        clickable: true
                        onClicked: ControlState.toggleMute(root.source)
                    }
                    SlimSlider {
                        anchors.left: micIcon.right
                        anchors.right: micPercent.left
                        anchors.leftMargin: 2
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.source?.audio?.volume ?? 0
                        muted: root.source?.audio?.muted ?? false
                        onMoved: v => ControlState.setVolume(root.source, v)
                    }
                    StyledText {
                        id: micPercent
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        horizontalAlignment: Text.AlignRight
                        text: Math.round((root.source?.audio?.volume ?? 0) * 100) + "%"
                        role: "caption"
                        font.features: ({ "tnum": 1 })
                        color: Colors.textOnSurfaceVariant
                    }
                }
                Repeater {
                    model: Style.volumePopupInput && ControlState.sources.length > 1 ? ControlState.sources : []

                    MenuRow {
                        required property var modelData
                        width: content.width
                        label: ControlState.nodeName(modelData)
                        checked: modelData === root.source
                        onClicked: ControlState.useSource(modelData)
                    }
                }

                // ---- Apps (only while something plays) ----------------------------------
                SectionLabel {
                    visible: root.streams.length > 0
                    text: "Apps"
                }
                Repeater {
                    model: root.streams

                    Item {
                        id: app
                        required property var modelData
                        readonly property bool appMuted: modelData?.audio?.muted ?? false
                        width: content.width
                        height: 34

                        // The app's icon: click to mute it.
                        MouseArea {
                            id: appIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ControlState.toggleMute(app.modelData)

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: Colors.textOnSurface
                                opacity: appIcon.pressed ? Style.pressTint : appIcon.containsMouse ? Style.hoverTint : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            }
                            AppIcon {
                                anchors.centerIn: parent
                                implicitSize: 22
                                source: AppAudio.appsLoaded >= 0 ? AppAudio.icon(app.modelData) : ""
                                name: AppAudio.name(app.modelData)
                                opacity: app.appMuted ? 0.4 : 1
                            }
                        }
                        SlimSlider {
                            anchors.left: appIcon.right
                            anchors.right: appPercent.left
                            anchors.leftMargin: 2
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            value: app.modelData?.audio?.volume ?? 0
                            muted: app.appMuted
                            onMoved: v => ControlState.setVolume(app.modelData, v)
                        }
                        StyledText {
                            id: appPercent
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            horizontalAlignment: Text.AlignRight
                            text: app.appMuted ? "Off" : Math.round((app.modelData?.audio?.volume ?? 0) * 100) + "%"
                            role: "caption"
                            font.features: ({ "tnum": 1 })
                            color: Colors.textOnSurfaceVariant
                        }
                    }
                }

                // ---- Sound settings… -------------------------------------------------------
                Item {
                    width: parent.width
                    height: 13

                    Rectangle {
                        x: 6
                        width: parent.width - 12
                        height: 1
                        anchors.verticalCenter: parent.verticalCenter
                        color: Style.alpha(Colors.textOnSurface, 0.1)
                    }
                }
                MenuRow {
                    width: content.width
                    label: "Sound settings…"
                    plain: true
                    onClicked: {
                        VolumeState.close();
                        ControlState.show("audio");
                    }
                }
            }
        }
    }

    // A small grey section title, like macOS menus.
    component SectionLabel: StyledText {
        leftPadding: 6
        topPadding: 8
        bottomPadding: 3
        role: "label"
        color: Colors.textOnSurfaceVariant
    }

    // A grey icon at either end of a slider; the left one can be clicked.
    component SoftIcon: MouseArea {
        id: soft
        property string name: ""
        property bool clickable: false
        width: 30
        height: 30
        hoverEnabled: clickable
        enabled: clickable
        cursorShape: clickable ? Qt.PointingHandCursor : Qt.ArrowCursor

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colors.textOnSurface
            opacity: soft.pressed ? Style.pressTint : soft.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Icon {
            anchors.centerIn: parent
            name: soft.name
            size: 18
            color: Colors.textOnSurfaceVariant
        }
    }

    // A menu line: ✓ (when checked) and a name; lights up under the mouse.
    component MenuRow: MouseArea {
        id: row
        property string label: ""
        property bool checked: false
        property bool plain: false          // no room for a check mark
        height: 28
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Colors.textOnSurface
            opacity: row.pressed ? Style.pressTint : row.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Icon {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            visible: row.checked
            name: "check"
            size: 16
            color: Colors.primary
        }
        StyledText {
            x: row.plain ? 8 : 28
            width: parent.width - x - 8
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            weight: row.checked ? 650 : Style.fontWeight
            elide: Text.ElideRight
        }
    }

    // Keys while open: arrows change the volume, M mutes.
    function step(delta) {
        ControlState.setVolume(sink, Math.max(0, Math.min(1, volume + delta * Style.volumeStep)));
    }
}
