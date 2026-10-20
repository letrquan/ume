import QtQuick
import qs.common
import qs.services

// While the screen is being recorded: a pulsing red dot and the time so far.
// It slides in when recording starts and out when it stops; click to stop.
Reveal {
    id: root

    // On the bar only while recording, and while it slides out after.
    // (`wanted`: the bar's slot reads it, see BarContent.)
    readonly property bool wanted: shown || implicitWidth > 0.5

    anchors.verticalCenter: parent?.verticalCenter
    // (The live activity bubble shows it instead, when it's on.)
    shown: Recorder.recording && !Activities.showRecording

    Clickable {
        spacing: 6
        tip: "Stop recording"
        tipDetail: "Recording for " + Recorder.elapsedText
        tipShortcut: "mine:record screen"
        onClicked: Recorder.stop()

        Rectangle {
            id: dot
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 10
            radius: 5
            color: Colors.error

            SequentialAnimation on opacity {
                running: Recorder.recording
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Recorder.elapsedText
            font.features: ({ "tnum": 1 })
            weight: 650
        }
    }
}
