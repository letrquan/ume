import QtQuick
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs.common
import qs.services

// One notification, as a glass card.
//   [picture]  App · 5m                     ✕
//              Summary
//              Body, a few lines…
//              [ Reply ] [ Action ] [ Action ]
//              ( Reply…                    ➤ )   ← chat apps, after Reply
// Click: the app's default action. Drag sideways: dismiss. Right-click:
// mute the app, or list only (RuleMenu). "×3" after the time: it came 3 times.
// As a popup (`popup: true`) it hides itself after a while (paused while
// the mouse is on it) and shows the time left as a thin line.
Item {
    id: card

    required property var entry
    property bool popup: false

    // Re-read the entry whenever its content changes. A copy: the same
    // object again wouldn't tell the bindings below that anything changed.
    readonly property var e: {
        Notifs.revision;
        return Object.assign({}, entry);
    }
    readonly property bool critical: e.urgency === NotificationUrgency.Critical
    readonly property var buttons: (e.actions ?? []).filter(a => a.identifier !== "default" && a.text !== "")
    // The app takes an answer typed right here (chat apps).
    readonly property bool canReply: Style.notifReply && (e.replyable ?? false)
    property bool replyOpen: false
    onCanReplyChanged: if (!canReply) replyOpen = false
    // The right-click menu (mute / list only) is open.
    property bool menuOpen: false
    readonly property bool hovered: hover.hovered
    // How long it stays as a popup; 0 = until you close it.
    readonly property int timeout: !popup || critical || e.timeout === 0 ? 0
                                 : e.timeout > 0 ? e.timeout : Style.notifTimeout

    implicitWidth: Style.notifWidth
    implicitHeight: content.implicitHeight + 28

    HoverHandler {
        id: hover
    }

    // Everything that slides away when you drag the card.
    Item {
        id: sheet
        width: card.width
        height: card.height

        Glass {
            anchors.fill: parent
            radius: Style.notifRadius
            border.color: card.critical ? Style.alpha(Colors.error, 0.7) : Style.islandBorder
        }

        // Click and drag; under the buttons so they get their clicks first.
        MouseArea {
            id: drag
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            drag.target: sheet
            drag.axis: Drag.XAxis
            drag.threshold: 8
            onReleased: {
                if (Math.abs(sheet.x) > card.width * 0.35)
                    flyOut.start();
                else
                    settle.start();
            }
            onClicked: if (Math.abs(sheet.x) < 4) Notifs.activate(card.e.key)
        }

        // Right-click (the MouseArea above takes only the left button). It
        // keeps the click (WithinBounds), so the list's click-outside-closes
        // underneath never sees it.
        TapHandler {
            gesturePolicy: TapHandler.WithinBounds
            acceptedButtons: Qt.RightButton
            onTapped: card.menuOpen = !card.menuOpen
        }

        Row {
            id: content
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 12

            // Picture: the notification's image with the app icon on its
            // corner, or just the app icon on a soft shape.
            Item {
                width: 44
                height: 44

                ClippingRectangle {
                    anchors.fill: parent
                    radius: 12
                    visible: card.e.image !== ""
                    color: Colors.surfaceContainerHigh

                    Image {
                        anchors.fill: parent
                        source: card.e.image
                        sourceSize: Qt.size(88, 88)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                Shape {
                    anchors.fill: parent
                    visible: card.e.image === ""
                    shape: card.critical ? "Cookie4Sided" : "Cookie9Sided"
                    color: card.critical ? Colors.errorContainer : Colors.secondaryContainer
                }

                // On the shape: the bare icon (the shape is its tile); on a
                // picture's corner: on its own small tile. A missing icon
                // gives the app's letter.
                AppIcon {
                    readonly property bool badge: card.e.image !== ""
                    anchors.centerIn: badge ? undefined : parent
                    anchors.right: badge ? parent.right : undefined
                    anchors.bottom: badge ? parent.bottom : undefined
                    anchors.rightMargin: -4
                    anchors.bottomMargin: -4
                    implicitSize: badge ? 20 : 30
                    visible: card.e.icon !== ""
                    source: card.e.icon
                    name: card.e.appName ?? ""
                    tiled: badge && Style.appIconStyle !== "plain"
                    letterTile: badge
                    letterColor: card.critical ? Colors.textOnErrorContainer : Colors.textOnSecondaryContainer
                }

                Icon {
                    anchors.centerIn: parent
                    visible: card.e.image === "" && card.e.icon === ""
                    name: card.critical ? "priority_high" : "notifications"
                    size: 22
                    color: card.critical ? Colors.textOnErrorContainer : Colors.textOnSecondaryContainer
                }
            }

            Column {
                width: parent.width - 44 - parent.spacing
                spacing: 3

                // App · time, and the close button.
                Item {
                    width: parent.width
                    height: 18

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28
                        text: (card.e.appName || "Notification") + "  ·  " + Notifs.ago(card.e.time)
                              + ((card.e.count ?? 1) > 1 ? "  ·  ×" + card.e.count : "")
                        role: "caption"
                        color: Colors.textOnSurfaceVariant
                        elide: Text.ElideRight
                    }

                    Clickable {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: 24
                        padding: 0
                        opacity: card.hovered || !card.popup ? 1 : 0
                        onClicked: flyOut.start()

                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                        Icon {
                            name: "close"
                            size: 16
                            color: Colors.textOnSurfaceVariant
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    text: card.e.summary
                    visible: text !== ""
                    role: "title"
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: card.e.body
                    visible: text !== ""
                    textFormat: Text.StyledText
                    linkColor: Colors.primary
                    color: Colors.textOnSurfaceVariant
                    wrapMode: Text.Wrap
                    maximumLineCount: card.popup ? Style.notifBodyLines : 6
                    elide: Text.ElideRight
                    onLinkActivated: link => { if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link); }
                }

                // The app's buttons (only while the app still listens).
                Flow {
                    width: parent.width
                    visible: card.buttons.length > 0 || card.canReply
                    topPadding: 6
                    spacing: 6

                    // Reply: opens the answer field below.
                    MouseArea {
                        id: replyButton
                        visible: card.canReply
                        width: replyRow.implicitWidth + 24
                        height: 28
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            card.replyOpen = !card.replyOpen;
                            if (card.replyOpen)
                                replyField.focusField();
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: card.replyOpen ? Colors.primary : Colors.secondaryContainer
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: card.replyOpen ? Colors.textOnPrimary : Colors.textOnSurface
                                opacity: replyButton.pressed ? Style.pressTint : replyButton.containsMouse ? Style.hoverTint : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            }
                        }

                        Row {
                            id: replyRow
                            anchors.centerIn: parent
                            spacing: 4
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "reply"
                                size: 15
                                color: card.replyOpen ? Colors.textOnPrimary : Colors.textOnSecondaryContainer
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Reply"
                                role: "label"
                                color: card.replyOpen ? Colors.textOnPrimary : Colors.textOnSecondaryContainer
                            }
                        }
                    }

                    Repeater {
                        model: card.buttons

                        MouseArea {
                            id: button
                            required property var modelData

                            width: label.implicitWidth + 24
                            height: 28
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifs.invoke(card.e.key, modelData.identifier)

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: Colors.secondaryContainer
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: Colors.textOnSurface
                                    opacity: button.pressed ? Style.pressTint : button.containsMouse ? Style.hoverTint : 0
                                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                                }
                            }

                            StyledText {
                                id: label
                                anchors.centerIn: parent
                                text: button.modelData.text
                                role: "label"
                                color: Colors.textOnSecondaryContainer
                            }
                        }
                    }
                }

                // The answer field: slides open under the buttons.
                Item {
                    width: parent.width
                    height: card.replyOpen ? replyField.implicitHeight + 8 : 0
                    clip: true
                    visible: height > 0

                    Behavior on height {
                        NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                    }

                    ReplyField {
                        id: replyField
                        y: 8
                        width: parent.width
                        hint: card.e.replyHint ?? ""
                        opacity: card.replyOpen ? 1 : 0
                        onSent: text => Notifs.reply(card.e.key, text)
                        onCancelled: card.replyOpen = false
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }
                }

                // The right-click menu: slides open at the bottom.
                Item {
                    width: parent.width
                    height: card.menuOpen ? ruleMenu.implicitHeight + 8 : 0
                    clip: true
                    visible: height > 0

                    Behavior on height {
                        NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                    }

                    RuleMenu {
                        id: ruleMenu
                        y: 8
                        width: parent.width
                        app: card.e.appName || "Notification"
                        opacity: card.menuOpen ? 1 : 0
                        onDone: card.menuOpen = false
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }
                }
            }
        }

        // Time left as a popup.
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            x: Style.notifRadius
            width: (parent.width - Style.notifRadius * 2) * card.remaining
            height: 2
            radius: 1
            color: Style.alpha(Colors.primary, 0.6)
            visible: card.timeout > 0
        }
    }

    // ---- Popup timer -----------------------------------------------------------
    property real remaining: 1
    NumberAnimation on remaining {
        running: card.timeout > 0
        paused: running && card.hovered
        from: 1
        to: 0
        duration: card.timeout
        onFinished: Notifs.hidePopup(card.e.key)
    }

    // ---- Drag / close ------------------------------------------------------------
    NumberAnimation {
        id: settle
        target: sheet
        property: "x"
        to: 0
        duration: Motion.normal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.defaultSpatial
    }

    SequentialAnimation {
        id: flyOut
        ParallelAnimation {
            NumberAnimation {
                target: sheet; property: "x"
                to: sheet.x < 0 ? -card.width * 1.1 : card.width * 1.1
                duration: Motion.fast; easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: sheet; property: "opacity"; to: 0
                duration: Motion.fast
            }
        }
        ScriptAction { script: Notifs.dismiss(card.e.key) }
    }
}
