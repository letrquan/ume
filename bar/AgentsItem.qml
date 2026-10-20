import QtQuick
import qs.common
import qs.services

// Claude Code sessions (services/Agents.qml): "◐ 2" working, "✳ 1" done or
// waiting for you (in the accent color). On the bar only while one works or
// waits; click: the one waiting longest (with none waiting, the next
// working one).
Reveal {
    id: root

    // (`wanted`: the bar's slot reads it, see BarContent.)
    readonly property bool wanted: shown || implicitWidth > 0.5

    anchors.verticalCenter: parent?.verticalCenter
    // (The live activity bubble shows them instead, when it's on.)
    shown: Agents.workingCount + Agents.waitingCount > 0 && !Activities.showAgents

    // Keeps the counts coming even with notifications off.
    Component.onCompleted: Agents.use(true)
    Component.onDestruction: Agents.use(false)

    Clickable {
        spacing: 5
        tip: "Claude Code"
        tipDetail: [Agents.workingCount > 0 ? Agents.workingCount + " working" : "",
                    Agents.waitingCount > 0 ? Agents.waitingCount + " waiting for you" : ""].filter(s => s !== "").join(" · ")
            + "\nClick: " + (Agents.waitingCount > 0 ? "the one waiting longest" : "the next one working")
        onClicked: Agents.showNext()

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: Agents.workingCount > 0
            text: "◐ " + Agents.workingCount
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: Agents.workingCount > 0 && Agents.waitingCount > 0
            text: "·"
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
