import QtQuick
import qs.common
import qs.services

// Little bars that dance to the music, next to the song in the middle
// island. Levels come from services/Visualizer.qml (cava); it only runs
// while this is on screen and something plays. Slides away when the music
// stops (Style.showVisualizer turns it off for good).
Reveal {
    id: root

    readonly property real barWidth: 3
    readonly property real gap: 2
    readonly property real tallest: 14

    anchors.verticalCenter: parent?.verticalCenter
    shown: Style.showVisualizer && Visualizer.playing

    // Counted in while really visible (a hidden bar item or island doesn't
    // keep cava running).
    readonly property bool wanted: visible && shown
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

    Item {
        implicitWidth: Visualizer.bars * (root.barWidth + root.gap) + 6
        implicitHeight: Style.itemHeight

        Row {
            anchors.centerIn: parent
            spacing: root.gap

            Repeater {
                model: Visualizer.bars

                Rectangle {
                    required property int index
                    readonly property real level: Visualizer.levels[index] ?? 0

                    anchors.verticalCenter: parent.verticalCenter
                    width: root.barWidth
                    // Grows from the middle; a dot when quiet.
                    height: root.barWidth + (root.tallest - root.barWidth) * level
                    radius: width / 2
                    color: Colors.primary
                    opacity: 0.55 + 0.45 * level
                    // No Behavior on height: cava already smooths, and an
                    // animation longer than a frame of cava (50 ms at
                    // Style.visualizerFps 20) never settles, so the bar would
                    // redraw on every vsync (and mango blur behind it again)
                    // while music plays.
                }
            }
        }
    }
}
