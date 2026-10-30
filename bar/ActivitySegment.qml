import QtQuick
import qs.common
import qs.services

// Live activities that go on (services/Activities.qml), at the front of the
// middle island, before the clock:
//
//      ( ◐ 2  ⏱ 24:13  ● 0:42 │ 09:55 Sun 18 Oct  ♪ song )
//        agents  focus  recording
//
// Click: Claude Code → the session waiting longest (or the next working
// one); the focus timer → pause / go on (right click: stop); recording →
// stop. Each part slides in and out on its own (Reveal), and the island
// grows both ways around the screen's middle, so nothing beside it moves.
// While a notification, a moment or a panel stands in for the island, the
// parts stay where they are (only faded, with the rest of the island): the
// island keeps its size, so the stand-in grows out of it and shrinks back
// to it exactly.
Row {
    id: root

    // The island is covered: no need to tick the agents' glyph.
    property bool folded: false

    readonly property bool any: Activities.bubbleShown && Intro.started

    anchors.verticalCenter: parent?.verticalCenter
    spacing: 0

    // ◐ ◑ take turns while a session works (once a second: the bar draws
    // again only then).
    property bool tick: false
    Timer {
        interval: 1000
        repeat: true
        running: Activities.showAgents && Agents.workingCount > 0 && root.any && !root.folded
        onTriggered: root.tick = !root.tick
    }

    // Claude Code sessions.
    Reveal {
        anchors.verticalCenter: parent.verticalCenter
        shown: Activities.showAgents && root.any

        Clickable {
            spacing: 5
            onClicked: Agents.showNext()

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: Agents.workingCount > 0 || Activities.previewing.agents
                text: (root.tick ? "◑ " : "◐ ") + Math.max(Agents.workingCount, Activities.previewing.agents ? 2 : 0)
                font.features: ({ "tnum": 1 })
                weight: 650
                color: Colors.textOnSurfaceVariant
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: Agents.waitingCount > 0
                text: "✳ " + Agents.waitingCount
                font.features: ({ "tnum": 1 })
                weight: 650
                color: Colors.primary
            }
        }
    }

    // The focus timer.
    Reveal {
        anchors.verticalCenter: parent.verticalCenter
        shown: Activities.showTimer && root.any

        Clickable {
            spacing: 4
            opacity: FocusTimer.paused ? 0.55 : 1
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    FocusTimer.reset();
                else
                    FocusTimer.toggle();
            }

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: FocusTimer.phase === "focus" || !FocusTimer.active ? "timer" : "coffee"
                size: 16
                color: FocusTimer.phase === "focus" || !FocusTimer.active ? Colors.primary : Colors.tertiary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: FocusTimer.active ? FocusTimer.timeText : "24:13"
                font.features: ({ "tnum": 1 })
                weight: 650
            }
        }
    }

    // Screen recording.
    Reveal {
        anchors.verticalCenter: parent.verticalCenter
        shown: Activities.showRecording && root.any

        Clickable {
            spacing: 6
            onClicked: Recorder.stop()

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                color: Colors.error

                SequentialAnimation on opacity {
                    running: Activities.showRecording && root.any && !root.folded
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Recorder.recording ? Recorder.elapsedText : "0:05"
                font.features: ({ "tnum": 1 })
                weight: 650
            }
        }
    }

    // The line between them and the clock, as far from the last part's text
    // as from the clock's: the parts have 6 px of padding, the clock 10 px
    // plus the island's spacing, so the line sits off its middle.
    Reveal {
        anchors.verticalCenter: parent.verticalCenter
        shown: root.any

        Item {
            implicitWidth: 14
            implicitHeight: 16

            Rectangle {
                x: (parent.width + 10 + Style.islandSpacing - 6) / 2
                // (In one bar, only the room.)
                visible: !Style.barJoined
                width: 1
                height: parent.height
                radius: 0.5
                color: Style.alpha(Colors.textOnSurface, 0.14)
            }
        }
    }
}
