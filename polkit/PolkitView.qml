import QtQuick
import Quickshell.Widgets
import Quickshell
import qs.common

// The password dialog apps ask for when they need admin rights (pkexec,
// Software updates, Disks...): the screen dims, a glass card springs up.
//
//      ╭────────────────────────────────────────────╮
//      │              (shield shape)                │
//      │         Authentication required            │
//      │   Authentication is needed to run          │
//      │   `/usr/bin/foo` as the super user         │
//      │        user  ·  org.freedesktop.policy…    │
//      │   (  ◆ ● ▲ ●                         →  )  │
//      │                  [ Cancel ]  [ Unlock ]    │
//      ╰────────────────────────────────────────────╯
//
// Plain QtQuick driven by properties, so it can be previewed with made-up
// data; PolkitWindow.qml feeds it the real request.
Item {
    id: root

    property bool open: false
    property string message: ""
    property string iconName: ""
    property string actionId: ""
    // The account whose password polkit asks for (PolkitWindow passes the
    // request's own; $USER is only the preview's stand-in).
    property string userName: Quickshell.env("USER") ?? ""
    property string prompt: ""             // e.g. "Password:"
    property bool visibleText: false       // polkit wants a non-secret answer
    property string info: ""               // extra line from polkit
    property bool infoIsError: false
    property string state_: "idle"         // idle | busy | failed

    readonly property alias field: field

    signal submitted(string text)
    signal cancelled()

    function focusField() {
        field.input.forceActiveFocus();
    }

    // "Password:" → "Password"
    readonly property string cleanPrompt: {
        const p = prompt.trim().replace(/:$/, "");
        return p !== "" ? p : (visibleText ? "Answer" : "Password");
    }
    readonly property string cleanMessage: message.trim().replace(/\.$/, "")

    Keys.onEscapePressed: root.cancelled()

    // ---- Dim the screen ---------------------------------------------------------------
    // The blurred wallpaper and the dim, fading together (Backdrop).
    Backdrop {
        anchors.fill: parent
        shown: root.open
        dim: Style.polkitDim
    }

    Item {
        id: card
        anchors.centerIn: parent
        width: Style.polkitWidth
        height: column.height + 52
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.9

        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
        }

        // Darkening off: no backdrop, so the card frosts its own piece.
        WallpaperFrost {
            anchors.fill: parent
            at: Qt.point(card.x, card.y)
            radius: Style.radiusDialog
            visible: Style.polkitDim <= 0
        }
        Glass {
            anchors.fill: parent
            radius: Style.radiusDialog
            color: Style.alpha(Colors.surfaceContainer, Style.polkitOpacity)
            border.color: root.state_ === "failed" ? Style.alpha(Colors.error, 0.7) : Style.islandBorder
        }

        // Clicks on the card stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: column
            anchors.horizontalCenter: parent.horizontalCenter
            y: 28
            width: parent.width - 52
            spacing: 14

            // Icon: the app's own if polkit names one, else a shield.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64
                height: 64

                Shape {
                    id: badge
                    anchors.fill: parent
                    shape: root.state_ === "failed" ? "Cookie4Sided" : root.state_ === "busy" ? "Sunny" : "Cookie12Sided"
                    color: root.state_ === "failed" ? Colors.errorContainer : Colors.primaryContainer
                    rotation: root.open ? 0 : -90
                    Behavior on rotation {
                        NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.slowSpatial }
                    }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 32
                    visible: root.iconName !== "" && status === Image.Ready
                    source: root.iconName !== "" ? Quickshell.iconPath(root.iconName, true) : ""
                    asynchronous: true
                }

                Icon {
                    anchors.centerIn: parent
                    visible: root.iconName === "" || Quickshell.iconPath(root.iconName, true) === ""
                    name: root.state_ === "failed" ? "lock" : "shield_lock"
                    size: 30
                    color: root.state_ === "failed" ? Colors.textOnErrorContainer : Colors.textOnPrimaryContainer
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Authentication required"
                role: "headline"
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.cleanMessage
                visible: text !== ""
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                color: Colors.textOnSurfaceVariant
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: [root.userName, root.actionId].filter(s => s !== "").join("  ·  ")
                role: "caption"
                color: Colors.outline
                elide: Text.ElideMiddle
            }

            PasswordField {
                id: field
                width: parent.width
                state_: root.state_
                placeholder: root.cleanPrompt
                visibleText: root.visibleText
                onAccepted: if (field.text.length > 0) root.submitted(field.text)
                Keys.onEscapePressed: root.cancelled()
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.info
                visible: text !== ""
                wrapMode: Text.Wrap
                role: "caption"
                color: root.infoIsError ? Colors.error : Colors.textOnSurfaceVariant
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                Clickable {
                    implicitHeight: 38
                    padding: 18
                    onClicked: root.cancelled()

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Cancel"
                        weight: 600
                    }
                }

                // The main button: filled, like the first notification action.
                MouseArea {
                    id: unlock
                    width: unlockLabel.implicitWidth + 40
                    height: 38
                    enabled: field.text.length > 0 && root.state_ !== "busy"
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.submitted(field.text)

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Colors.primary
                        opacity: unlock.enabled ? 1 : 0.4
                        scale: unlock.pressed ? 0.94 : 1
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        Behavior on scale {
                            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: Colors.textOnPrimary
                            opacity: unlock.pressed ? Style.pressTint : unlock.containsMouse ? Style.hoverTint : 0
                        }
                    }

                    StyledText {
                        id: unlockLabel
                        anchors.centerIn: parent
                        text: root.state_ === "busy" ? "Checking…" : "Unlock"
                        weight: 700
                        color: Colors.textOnPrimary
                    }
                }
            }
        }
    }
}
