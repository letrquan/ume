pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import qs.common

// The polkit agent: apps that need admin rights ask it for your password.
// Only ONE agent can run per session, so Noctalia's has to be off first
// ([shell] polkit_agent = false, flipped by `mine on`).
//
// Creating this singleton registers the agent on the system bus, so only
// shell.qml touches it (never previews or tests).
Singleton {
    id: root

    readonly property bool active: agent.isActive
    readonly property var flow: agent.flow
    readonly property bool registered: agent.isRegistered

    // The dialog window exists while a request is active, plus its exit
    // animation.
    property bool mapped: false

    onActiveChanged: {
        if (active) {
            unmap.stop();
            mapped = true;
        } else {
            unmap.restart();
        }
    }

    Timer {
        id: unmap
        interval: Motion.normal + 200
        onTriggered: root.mapped = false
    }

    PolkitAgent {
        id: agent
    }

    // One line in the shell log to check the handover worked (another agent,
    // e.g. Noctalia's, makes the registration fail).
    Timer {
        running: true
        interval: 3000
        onTriggered: {
            if (agent.isRegistered)
                console.info("polkit: agent registered at", agent.path);
            else
                console.warn("polkit: agent NOT registered (is Noctalia's polkit_agent still on?)");
        }
    }
}
