import QtQuick
import Quickshell
import qs.common
import qs.services

// One port a program of yours listens on (a dev server, mostly):
//   [icon] next-server (v1      :20128   all interfaces
// Click: opens http://localhost:20128 in the browser. On hover the place
// line gives way to two buttons: copy the address, and ✕ = stop it, which
// asks first (a red "Stop"; a second click sends SIGTERM, see
// SysmonState.stopListener). The rows stay; what's in them changes when the
// list is read again, and a question goes away when its row shows another port.
MouseArea {
    id: root

    // { port, pids, name, scope, address, url } (SysmonState.listening), or null
    property var listener: null
    // Its app (desktop entry), if it has one: the icon; and the name shown.
    property var entry: null
    property string name: ""

    signal opened()

    // The port the red "Stop" is for.
    property int asking: 0
    readonly property bool askingHere: asking !== 0 && asking === listener?.port
    property bool copied: false
    readonly property bool showButtons: containsMouse || askingHere

    implicitHeight: 30
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
        if (!listener)
            return;
        SysmonState.openListener(listener);
        root.opened();
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Colors.textOnSurface
        opacity: root.containsMouse ? Style.hoverTint : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    }

    // ---- icon + name ----------------------------------------------------------------
    Item {
        id: iconBox
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 22

        AppIcon {
            anchors.fill: parent
            visible: root.entry !== null
            source: root.entry ? Quickshell.iconPath(root.entry.icon, "application-x-executable") : ""
            name: root.entry?.name ?? ""
        }
        // No app: a soft round chip with a glyph.
        Rectangle {
            anchors.fill: parent
            visible: root.entry === null
            radius: width / 2
            color: Style.alpha(Colors.textOnSurface, 0.08)

            Icon {
                anchors.centerIn: parent
                name: "lan"
                size: 14
                color: Colors.textOnSurfaceVariant
            }
        }
    }

    StyledText {
        anchors.left: iconBox.right
        anchors.leftMargin: 10
        anchors.right: portText.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.name
        elide: Text.ElideRight
    }

    StyledText {
        id: portText
        anchors.right: place.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.listener ? ":" + root.listener.port : ""
        font.features: ({ "tnum": 1 })
        weight: 650
    }

    // ---- where it can be reached ------------------------------------------------------
    Rectangle {
        id: place
        readonly property bool exposed: root.listener?.scope === "all"
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 104
        height: 22
        radius: height / 2
        color: exposed ? Style.alpha(Colors.error, 0.16) : Style.alpha(Colors.textOnSurface, 0.07)
        opacity: root.showButtons ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        StyledText {
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 12)
            elide: Text.ElideRight
            text: !root.listener ? ""
                : root.listener.scope === "all" ? "all interfaces"
                : root.listener.scope === "local" ? "this computer"
                : root.listener.address
            role: "label"
            color: place.exposed ? Colors.error : Colors.textOnSurfaceVariant
        }
    }

    // ---- copy the address, stop it: on hover, over the place -------------------------
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        visible: opacity > 0.01
        opacity: root.showButtons ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        MouseArea {
            id: copyButton
            width: 22
            height: 22
            visible: !root.askingHere
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                SysmonState.copyListener(root.listener);
                root.copied = true;
                uncopy.restart();
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Colors.textOnSurface
                opacity: copyButton.containsMouse ? Style.pressTint : 0
            }
            Icon {
                anchors.centerIn: parent
                name: root.copied ? "check" : "content_copy"
                size: 14
                color: root.copied ? Colors.primary : Colors.textOnSurfaceVariant
            }
        }

        MouseArea {
            id: stopButton
            width: root.askingHere ? stopText.implicitWidth + 24 : 22
            height: 22
            visible: (root.listener?.pids?.length ?? 0) > 0
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.askingHere) {
                    SysmonState.stopListener(root.listener);
                    root.asking = 0;
                } else {
                    root.asking = root.listener?.port ?? 0;
                    forget.restart();
                }
            }

            Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial } }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: root.askingHere ? Colors.error : Colors.textOnSurface
                opacity: root.askingHere ? 1 : stopButton.containsMouse ? Style.pressTint : 0
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
            Icon {
                anchors.centerIn: parent
                visible: !root.askingHere
                name: "close"
                size: 14
                color: stopButton.containsMouse ? Colors.error : Colors.textOnSurfaceVariant
            }
            StyledText {
                id: stopText
                anchors.centerIn: parent
                visible: root.askingHere
                text: "Stop"
                role: "label"
                color: Colors.textOnError
            }
        }
    }

    // The question and the ✓ go away on their own, or when the row shows another port.
    Timer {
        id: forget
        interval: 3500
        onTriggered: root.asking = 0
    }
    Timer {
        id: uncopy
        interval: 1400
        onTriggered: root.copied = false
    }
    onListenerChanged: if (asking !== 0 && listener?.port !== asking) asking = 0
}
