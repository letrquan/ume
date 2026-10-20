import QtQuick
import qs.common
import qs.services

// The bars dancing to the music, bigger, for the Now Playing card. Same
// levels as the bar's (services/Visualizer.qml, cava); counted in only while
// really on screen and `running`, so cava stops with the card.
Item {
    id: root

    property bool running: false
    property color color: Colors.primary
    readonly property real barWidth: 4
    readonly property real gap: 3
    readonly property real tallest: 22

    implicitWidth: Visualizer.bars * (barWidth + gap) - gap
    implicitHeight: tallest
    opacity: running ? 1 : 0.35

    Behavior on opacity { NumberAnimation { duration: Motion.normal } }

    readonly property bool wanted: visible && running && Style.showVisualizer
    property bool counted: false
    onWantedChanged: count()
    Component.onCompleted: count()
    Component.onDestruction: if (counted) Visualizer.use(-1)
    function count() {
        if (wanted !== counted) {
            Visualizer.use(wanted ? 1 : -1);
            counted = wanted;
        }
    }

    Row {
        anchors.bottom: parent.bottom
        spacing: root.gap

        Repeater {
            model: Visualizer.bars

            Rectangle {
                required property int index
                readonly property real level: root.running ? (Visualizer.levels[index] ?? 0) : 0

                anchors.bottom: parent.bottom
                width: root.barWidth
                // Grows up from the bottom; a dot when quiet. No Behavior:
                // cava already smooths (see bar/MusicBars.qml).
                height: root.barWidth + (root.tallest - root.barWidth) * level
                radius: width / 2
                color: root.color
                opacity: 0.55 + 0.45 * level
            }
        }
    }
}
