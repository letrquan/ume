import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The password dialog window. One window (on the screen mango picks),
// taking the keyboard so you can type the password right away. It gets the
// live request (`flow`, a polkit AuthFlow) from shell.qml and only exists
// while a request is active (PolkitService.mapped).
// It never touches the agent itself, so it can be loaded without one.
PanelWindow {
    id: root

    // The polkit AuthFlow (or null while closing).
    property var flow: null
    property bool active: false

    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }
    property string state_: "idle"      // idle | busy | failed

    Component.onCompleted: {
        view.focusField();
    }

    // A new request in the same window (one queued behind the last, or a
    // second one right after): an empty field, never the last password.
    onFlowChanged: {
        view.field.text = "";
        state_ = "idle";
        view.focusField();
    }

    // Who asked, when the shell can tell. Its own two admin actions run
    // pkexec with a fixed command, and polkit's message shows that command
    // between quotes (whole, it's short). Any other request to run
    // something as root says it isn't from the shell, so a look-alike can't
    // pass for Updates.
    function quoted(message, command) {
        const i = message.indexOf(command);
        return i > 0 && message.indexOf(command, i + 1) < 0
            && /[`'"‘“«]/.test(message.charAt(i - 1)) && /['"’”»]/.test(message.charAt(i + command.length));
    }
    readonly property string origin: {
        const f = root.flow;
        if (!f || f.actionId !== "org.freedesktop.policykit.exec")
            return "";
        if (UpdateRun.askingPassword && quoted(f.message, UpdateRun.rootCommand))
            return "From Updates (this shell)";
        if (WindowsBoot.busy && quoted(f.message, WindowsBoot.rootCommand))
            return "From Restart to Windows (this shell)";
        return "Not from this shell: check the command";
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "mine-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While a request is active the whole screen takes clicks, so nothing
    // behind can be clicked by accident (clicking outside does NOT cancel:
    // a stray click shouldn't throw away a password prompt).
    mask: root.active ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    function cancel() {
        root.flow?.cancelAuthenticationRequest();
    }

    function submit(text) {
        if (!root.flow || !root.flow.isResponseRequired)
            return;
        root.state_ = "busy";
        root.flow.submit(text);
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true

        function onAuthenticationFailed() {
            root.state_ = "failed";
            view.field.text = "";
            view.focusField();
        }
        function onIsCompletedChanged() {
            if (root.flow?.isCompleted)
                view.field.text = "";
        }
        function onIsResponseRequiredChanged() {
            // polkit asks again after a wrong password.
            if (root.flow?.isResponseRequired && root.state_ === "busy")
                root.state_ = "idle";
        }
    }

    PolkitView {
        id: view
        anchors.fill: parent
        open: root.ready && root.active

        message: root.flow?.message ?? ""
        iconName: root.flow?.iconName ?? ""
        actionId: root.flow?.actionId ?? ""
        origin: root.origin
        // Whose password polkit wants: the identity it picked (the first
        // admin it lists, not always you), by login name (the full name is
        // free text, any account could be called "root" there).
        userName: root.flow?.selectedIdentity?.string ?? ""
        prompt: root.flow?.inputPrompt ?? ""
        visibleText: root.flow?.responseVisible ?? false
        info: root.flow?.supplementaryMessage ?? ""
        infoIsError: root.flow?.supplementaryIsError ?? false
        state_: root.state_

        onSubmitted: text => root.submit(text)
        onCancelled: root.cancel()

        // Typing again after a wrong password clears the red.
        Connections {
            target: view.field.input
            function onTextChanged() {
                if (root.state_ === "failed" && view.field.text.length > 0)
                    root.state_ = "idle";
            }
        }
    }
}
