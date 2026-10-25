import QtQuick
import qs.common
import qs.services

// Tailscale: the switch up top (once you're its operator), this laptop
// with its address, the other devices on your tailnet (online first, the
// ones gone for a while folded away), and the exit node when a device
// offers one. Click a device: its address is copied (Style.tailscaleCopy:
// the IP or its MagicDNS name; right click or a long press: the other).
Column {
    id: root

    spacing: 6

    property bool showOld: false
    readonly property var recent: Tailscale.peers.filter(p => !Tailscale.isOld(p))
    readonly property var old: Tailscale.peers.filter(p => Tailscale.isOld(p))
    readonly property var me: Tailscale.self

    // Who may change things can change behind our back (sudo in a
    // terminal): look again each time the page opens.
    Component.onCompleted: {
        Tailscale.use("open", true);
        Tailscale.readPrefs();
    }
    Component.onDestruction: Tailscale.use("open", false)

    function detailOf(d) {
        if (Tailscale.copied.id === d.id)
            return "Copied " + Tailscale.copied.text;
        if (d.online)
            return (d.ipv4 || d.dns) + (d.exitNode ? " · exit node" : "");
        return (d.expired ? "Key expired · " : "") + "Last seen " + Tailscale.ago(d.lastSeen);
    }

    PageHeader {
        width: parent.width
        title: "Tailscale"
        hasSwitch: Tailscale.canControl && Tailscale.switchable
        checked: Tailscale.busy === "up" ? true : Tailscale.busy === "down" ? false : Tailscale.running
        onFlipped: Tailscale.toggle()

        Clickable {
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: 32
            onClicked: {
                Tailscale.refresh();
                Tailscale.readPrefs();
            }
            Icon { name: "refresh"; size: 18 }
        }
    }

    // ---- This laptop -----------------------------------------------------------------------
    MouseArea {
        id: selfRow
        width: parent.width
        height: 64
        visible: root.me !== null && Tailscale.state !== ""
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => Tailscale.copy(root.me, mouse.button === Qt.RightButton)
        onPressAndHold: Tailscale.copy(root.me, true)

        Rectangle {
            anchors.fill: parent
            radius: Style.inner(Style.ccRadius, Style.ccPadding)
            color: Colors.textOnSurface
            opacity: selfRow.pressed ? Style.pressTint : selfRow.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }

        Item {
            id: badge
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: 48

            Shape {
                anchors.fill: parent
                shape: Tailscale.running ? "Cookie9Sided" : "Circle"
                color: Tailscale.running ? Colors.primaryContainer : Style.alpha(Colors.textOnSurface, 0.1)
                rotation: Tailscale.running ? 0 : -40
                Behavior on rotation {
                    NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                }

                RotationAnimation on rotation {
                    running: Tailscale.busy === "up" || Tailscale.busy === "down"
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 1600
                }
            }
            Icon {
                anchors.centerIn: parent
                name: "vpn_lock"
                size: 24
                fill: Tailscale.running ? 1 : 0
                color: Tailscale.running ? Colors.textOnPrimaryContainer : Colors.textOnSurfaceVariant
            }
        }

        Column {
            anchors.left: badge.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            StyledText {
                width: parent.width
                text: root.me ? root.me.name + "  ·  this laptop" : ""
                role: "title"
                elide: Text.ElideRight
            }
            StyledText {
                width: parent.width
                text: root.me && Tailscale.copied.id === root.me.id ? "Copied " + Tailscale.copied.text
                    : Tailscale.summary + (Tailscale.running && root.me?.ipv4 ? " · " + root.me.ipv4 : "")
                role: "caption"
                color: Colors.textOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }

    // ---- What went wrong, what to do -------------------------------------------------------
    StyledText {
        x: 8
        width: parent.width - 16
        visible: Tailscale.actionError !== ""
        text: "Couldn't: " + Tailscale.actionError
        role: "caption"
        color: Colors.error
        wrapMode: Text.Wrap
    }

    // Not the operator yet: the one command that fixes it.
    Rectangle {
        width: parent.width
        height: setup.implicitHeight
        visible: Tailscale.installed && Tailscale.prefsKnown && !Tailscale.canControl && Tailscale.state !== ""
        radius: Style.inner(Style.ccRadius, Style.ccPadding)
        color: Style.alpha(Colors.textOnSurface, 0.06)

        Column {
            id: setup
            width: parent.width
            padding: 12
            spacing: 6

            StyledText {
                width: parent.width - 24
                wrapMode: Text.Wrap
                role: "caption"
                color: Colors.textOnSurfaceVariant
                text: "To turn Tailscale on and off from here, run this once in a terminal:"
            }
            Item {
                width: parent.width - 24
                height: Math.max(command.implicitHeight, copyButton.height)

                StyledText {
                    id: command
                    anchors.left: parent.left
                    anchors.right: copyButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.WrapAnywhere
                    text: Tailscale.operatorCommand
                    role: "label"
                    font.family: "monospace"
                    color: Colors.textOnSurface
                }
                PillButton {
                    id: copyButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Tailscale.copied.id === "operator" ? "Copied" : "Copy"
                    filled: true
                    onClicked: Tailscale.copyOperatorCommand()
                }
            }
        }
    }

    StyledText {
        x: 8
        width: parent.width - 16
        visible: Tailscale.state === "NeedsLogin" || Tailscale.state === "NeedsMachineAuth"
        text: Tailscale.state === "NeedsLogin" ? "Not logged in: run tailscale up in a terminal and log in in the browser"
            : "This device waits for an admin to approve it in Tailscale's admin console"
        role: "caption"
        color: Colors.textOnSurfaceVariant
        wrapMode: Text.Wrap
    }

    // tailscaled's own warnings (DNS set-up and such).
    Repeater {
        model: Tailscale.running ? Tailscale.health.slice(0, 2) : []

        Row {
            required property string modelData
            x: 8
            width: root.width - 16
            spacing: 8

            Icon {
                name: "warning"
                size: 16
                color: Colors.textOnSurfaceVariant
            }
            StyledText {
                width: parent.width - 24
                text: parent.modelData
                role: "caption"
                color: Colors.textOnSurfaceVariant
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }
    }

    // ---- Exit node: only when a device offers one ------------------------------------------
    StyledText {
        x: 8
        visible: Tailscale.running && Tailscale.exitOptions.length > 0
        text: "Exit node"
        role: "label"
        color: Colors.textOnSurfaceVariant
    }
    Column {
        width: parent.width
        spacing: 2
        visible: Tailscale.running && Tailscale.exitOptions.length > 0
        enabled: Tailscale.canControl && Tailscale.busy === ""
        opacity: enabled ? 1 : 0.55

        ListItem {
            width: parent.width
            icon: "public"
            label: "None"
            detail: "Internet traffic goes out as usual"
            current: Tailscale.exitNode === null
            onClicked: Tailscale.setExitNode(null)
        }
        Repeater {
            model: Tailscale.exitOptions

            ListItem {
                required property var modelData
                width: parent.width
                icon: Tailscale.glyphFor(modelData)
                label: modelData.name
                detail: !modelData.online ? "Offline" : modelData.exitNode ? "Internet traffic goes through it" : ""
                current: modelData.exitNode
                busy: Tailscale.busy === "exit" && !modelData.exitNode
                onClicked: Tailscale.setExitNode(modelData)
            }
        }
    }

    // ---- The other devices -----------------------------------------------------------------
    StyledText {
        x: 8
        visible: Tailscale.peers.length > 0
        text: "Devices"
        role: "label"
        color: Colors.textOnSurfaceVariant
    }

    Flickable {
        width: parent.width
        height: Math.min(contentHeight, 6 * 50)
        visible: Tailscale.peers.length > 0
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: parent.width
            spacing: 2

            Repeater {
                model: root.recent
                DeviceRow {}
            }

            ListItem {
                width: list.width
                visible: root.old.length > 0
                icon: "history"
                label: root.old.length + (root.old.length === 1 ? " older device" : " older devices")
                detail: "Offline for over " + Style.tailscaleHideAfterDays + (Style.tailscaleHideAfterDays === 1 ? " day" : " days")
                trailing: root.showOld ? "expand_less" : "expand_more"
                onClicked: root.showOld = !root.showOld
            }

            Repeater {
                model: root.showOld ? root.old : []
                DeviceRow {}
            }
        }
    }

    // ---- Nothing to show -------------------------------------------------------------------
    EmptyState {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !Tailscale.known || !Tailscale.installed || Tailscale.state === ""
        textWidth: parent.width - 32
        icon: !Tailscale.known ? "hourglass_empty" : "vpn_key_off"
        title: !Tailscale.known ? "Looking…"
            : !Tailscale.installed ? "Tailscale isn't installed"
            : "Tailscale isn't running"
        hint: !Tailscale.known ? ""
            : !Tailscale.installed ? "sudo pacman -S tailscale, then sudo systemctl enable --now tailscaled and tailscale up"
            : "sudo systemctl enable --now tailscaled" + (Tailscale.readError !== "" ? "\n(" + Tailscale.readError + ")" : "")
    }

    // A device: click copies its address, right click / long press the other one.
    component DeviceRow: ListItem {
        required property var modelData
        readonly property var d: modelData

        width: list.width
        icon: Tailscale.glyphFor(d)
        label: d.name
        detail: root.detailOf(d)
        opacity: d.online ? 1 : 0.6
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => Tailscale.copy(d, mouse.button === Qt.RightButton)
        onPressAndHold: Tailscale.copy(d, true)
    }

    // A pill button: the main one filled (like the phone page's).
    component PillButton: MouseArea {
        id: button
        property string text: ""
        property bool filled: false

        width: label.implicitWidth + 32
        height: 32
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: button.filled ? Colors.primary : "transparent"
            scale: button.pressed ? 0.94 : 1
            Behavior on scale {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: button.filled ? Colors.textOnPrimary : Colors.textOnSurface
                opacity: button.pressed ? Style.pressTint : button.containsMouse ? Style.hoverTint : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }
        }
        StyledText {
            id: label
            anchors.centerIn: parent
            text: button.text
            role: "label"
            weight: button.filled ? 700 : 600
            color: button.filled ? Colors.textOnPrimary : Colors.textOnSurface
        }
    }
}
