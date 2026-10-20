import QtQuick
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs.common
import qs.services

// The notification island. It grows out of the middle island (MorphCard:
// it starts with the island's exact size and glass, then one smooth curve
// carries it to the card), shows the notification, and shrinks back into
// the island when it's done.
//
//      ╭──────────────────────────────────────────╮
//      │ (icon)  Discord · 3 new                ✕ │
//      │         Minh                             │
//      │         are you coming tonight?          │
//      │         [ Reply ]  [ Mark read ]         │
//      │         ( Reply to Minh…            ➤ )  │   ← after Reply
//      ╰─────────────────── ──── ─────────────────╯   ← time left
//
// Click: the app's default action. Drag up: dismiss. Hover: stay, and read
// the whole text. Reply (chat apps that allow it): a field opens in the
// card and the keyboard goes there; Enter sends, Esc closes it. When several arrive they take turns: the old one leaves
// upward while the next comes up from below and the card resizes.
// Right-click: mute the app, or list only (RuleMenu). "×3": it came 3 times.
// Plain QtQuick (plus Notifs), so it can be previewed outside the shell.
Item {
    id: root

    // The newest notification waiting to show (null = none, shrink back).
    property var entry: null
    // How many are waiting, this one included.
    property int count: 0
    // Width of the middle island right now: where we start and end.
    property real startWidth: 200
    property bool open: false

    // While true the bar hides the real middle island.
    readonly property bool covering: morph.covering
    // Fully back in the island: the window can go.
    readonly property bool settled: morph.settled
    readonly property alias cardItem: morph.card
    readonly property bool hovered: hover.hovered
    readonly property bool revealed: morph.revealed

    // ---- What is on the card -----------------------------------------------------
    // `shown` stays on the last notification while shrinking back.
    property var shown: null
    // A copy each time its content changes (the same object again wouldn't
    // tell the bindings below that anything changed).
    readonly property var e: {
        Notifs.revision;
        return shown ? Object.assign({}, shown) : null;
    }
    readonly property bool critical: e?.urgency === NotificationUrgency.Critical
    readonly property var buttons: (e?.actions ?? []).filter(a => a.identifier !== "default" && a.text !== "")
    readonly property bool canReply: Style.notifReply && (e?.replyable ?? false)
    // The reply field is open on this card (it holds the card in place).
    readonly property bool replyOpen: Notifs.replying !== "" && Notifs.replying === (shown?.key ?? "")
    // The right-click menu is open (not together with the reply field).
    property bool menuOpen: false
    // Waiting from the same app as the one showing (it included): "3 new".
    readonly property int sameApp: shown ? Notifs.popups.filter(p => (p.appName || "") === (shown.appName || "")).length : 0
    readonly property int timeout: !e || critical || e.timeout === 0 ? 0
                                 : e.timeout > 0 ? e.timeout : Style.notifTimeout

    readonly property real cardWidth: Math.max(Style.notifWidth, startWidth)
    readonly property real cardHeight: Math.min(Style.notifMaxHeight + (replyOpen ? 46 : menuOpen ? 40 : 0), content.implicitHeight + 30)

    onOpenChanged: {
        timer.stop();
        remaining = 1;
        if (open && timeout > 0)
            timer.restart();
    }

    onEntryChanged: {
        if (!entry)
            return;          // keep showing the last one while shrinking
        if (!shown || !revealed)
            shown = entry;
        else if (entry.key !== shown.key && !replyOpen)
            swap.restart();  // (while replying, the next one waits)
    }
    // Done replying: on to whatever came in meanwhile.
    onReplyOpenChanged: {
        if (replyOpen)
            menuOpen = false;
        if (!replyOpen && entry && shown && entry.key !== shown.key && revealed)
            swap.restart();
    }

    onShownChanged: {
        menuOpen = false;
        timer.stop();
        remaining = 1;
        if (timeout > 0 && open)
            timer.restart();
    }

    // Next notification: the old content leaves upward, the new one comes
    // up from below while the card's height glides to fit it (MorphCard).
    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: content; property: "opacity"; to: 0; duration: Motion.contentOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
            NumberAnimation { target: shift; property: "y"; to: -10; duration: Motion.contentOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
        }
        ScriptAction {
            script: {
                root.shown = root.entry;
                shift.y = 12;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: content; property: "opacity"; to: 1; duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            NumberAnimation { target: shift; property: "y"; to: 0; duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }
    }

    // ---- Time left ---------------------------------------------------------------------
    property real remaining: 1
    NumberAnimation {
        id: timer
        target: root
        property: "remaining"
        from: 1
        to: 0
        duration: Math.max(1, root.timeout)
        paused: running && (root.hovered || root.replyOpen)
        onFinished: if (root.shown) Notifs.hidePopup(root.shown.key)
    }

    // ---- The card ------------------------------------------------------------------------
    MorphCard {
        id: morph

        anchors.fill: parent
        fromX: (width - root.startWidth) / 2
        fromY: Style.marginEdge
        fromWidth: root.startWidth
        toWidth: root.cardWidth
        toHeight: root.cardHeight
        radius: Style.notifIslandRadius
        glassOpacity: Style.notifOpacity
        borderColor: root.critical ? Style.alpha(Colors.error, 0.8) : Style.islandBorder
        open: root.open

        HoverHandler {
            id: hover
        }

        // Click: open it. Drag up: away with it. Under the buttons.
        MouseArea {
            id: press
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // Measured with the card's own offset added back, so the card
            // moving under the pointer doesn't feed back into the drag.
            property real startY: 0
            property bool dragging: false

            onPressed: mouse => {
                pullBack.stop();
                startY = mouse.y + morph.pullY;
                dragging = false;
            }
            onPositionChanged: mouse => {
                const dy = mouse.y + morph.pullY - startY;
                if (dy < -6)
                    dragging = true;
                if (dragging)
                    morph.pullY = Math.min(0, dy) * 0.6;
            }
            onReleased: {
                const far = morph.pullY < -28;
                pullBack.restart();
                if (far && root.shown)
                    Notifs.dismiss(root.shown.key);
            }
            onClicked: if (!dragging && root.shown) Notifs.activate(root.shown.key)
        }

        // Right-click (the MouseArea above takes only the left button).
        TapHandler {
            gesturePolicy: TapHandler.WithinBounds
            acceptedButtons: Qt.RightButton
            onTapped: {
                if (!root.shown)
                    return;
                if (root.replyOpen)
                    Notifs.replying = "";
                root.menuOpen = !root.menuOpen;
            }
        }

        NumberAnimation {
            id: pullBack
            target: morph
            property: "pullY"
            to: 0
            duration: Motion.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.emphasizedDecel
        }

        Row {
            id: content

            x: 16
            y: 15
            width: root.cardWidth - 32
            spacing: 13
            // Moves for the swap to the next notification.
            transform: Translate {
                id: shift
            }

            // Picture with the app icon on its corner, or the app icon on
            // a shape that turns into place as the card opens.
            Item {
                width: 46
                height: 46

                ClippingRectangle {
                    anchors.fill: parent
                    radius: 14
                    visible: (root.e?.image ?? "") !== ""
                    color: Colors.surfaceContainerHigh

                    Image {
                        anchors.fill: parent
                        source: root.e?.image ?? ""
                        sourceSize: Qt.size(92, 92)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                Shape {
                    anchors.fill: parent
                    visible: (root.e?.image ?? "") === ""
                    shape: root.critical ? "Cookie4Sided" : "Cookie9Sided"
                    color: root.critical ? Colors.errorContainer : Colors.primaryContainer
                    rotation: root.revealed ? 0 : -60

                    Behavior on rotation {
                        NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.slowSpatial }
                    }
                }

                // On the shape: the bare icon (the shape is its tile); on a
                // picture's corner: on its own small tile. A missing icon
                // gives the app's letter.
                AppIcon {
                    readonly property bool badge: (root.e?.image ?? "") !== ""
                    anchors.centerIn: badge ? undefined : parent
                    anchors.right: badge ? parent.right : undefined
                    anchors.bottom: badge ? parent.bottom : undefined
                    anchors.rightMargin: -4
                    anchors.bottomMargin: -4
                    implicitSize: badge ? 20 : 28
                    visible: (root.e?.icon ?? "") !== ""
                    source: root.e?.icon ?? ""
                    name: root.e?.appName ?? ""
                    tiled: badge && Style.appIconStyle !== "plain"
                    letterTile: badge
                    letterColor: root.critical ? Colors.textOnErrorContainer : Colors.textOnPrimaryContainer
                }

                Icon {
                    anchors.centerIn: parent
                    visible: (root.e?.image ?? "") === "" && (root.e?.icon ?? "") === ""
                    name: root.critical ? "priority_high" : "notifications"
                    size: 22
                    color: root.critical ? Colors.textOnErrorContainer : Colors.textOnPrimaryContainer
                }
            }

            Column {
                width: parent.width - 46 - parent.spacing
                spacing: 2

                // App · time, waiting count, close.
                Item {
                    width: parent.width
                    height: 18

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - tools.width - 8
                        text: (root.e?.appName || "Notification") + "  ·  "
                              + (root.sameApp > 1 ? root.sameApp + " new" : Notifs.ago(root.e?.time ?? Date.now()))
                              + ((root.e?.count ?? 1) > 1 ? "  ·  ×" + root.e.count : "")
                        role: "caption"
                        color: root.critical ? Colors.error : Colors.primary
                        elide: Text.ElideRight
                    }

                    Row {
                        id: tools
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        // More waiting: opens the list.
                        Clickable {
                            visible: root.count > 1
                            implicitHeight: 20
                            padding: 7
                            onClicked: Notifs.setCenter(true)

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                // All from the same app: the header says how many.
                                text: root.count > root.sameApp ? "+" + (root.count - 1) : "See all"
                                role: "label"
                                color: Colors.textOnSurfaceVariant
                            }
                        }

                        Clickable {
                            implicitHeight: 22
                            padding: 0
                            opacity: root.hovered ? 1 : 0
                            onClicked: if (root.shown) Notifs.dismiss(root.shown.key)

                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                            Icon {
                                name: "close"
                                size: 16
                                color: Colors.textOnSurfaceVariant
                            }
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    text: root.e?.summary ?? ""
                    visible: text !== ""
                    role: "title"
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: root.e?.body ?? ""
                    visible: text !== ""
                    textFormat: Text.StyledText
                    linkColor: Colors.primary
                    color: Colors.textOnSurfaceVariant
                    wrapMode: Text.Wrap
                    maximumLineCount: root.hovered ? 6 : Style.notifBodyLines
                    elide: Text.ElideRight
                    onLinkActivated: link => { if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link); }
                }

                // The app's buttons: the first one filled, the rest soft.
                // Reply (if the app takes answers here) comes first.
                Flow {
                    width: parent.width
                    visible: root.buttons.length > 0 || root.canReply
                    topPadding: 8
                    spacing: 6

                    MouseArea {
                        id: replyButton
                        visible: root.canReply
                        width: replyRow.implicitWidth + 28
                        height: 30
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.replyOpen) {
                                Notifs.replying = "";
                            } else if (root.shown) {
                                Notifs.replying = root.shown.key;
                                // Once the window has the keyboard.
                                Qt.callLater(() => replyField.focusField());
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Colors.primary
                            scale: replyButton.pressed ? 0.94 : 1
                            Behavior on scale {
                                NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: Colors.textOnPrimary
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
                                name: root.replyOpen ? "close" : "reply"
                                size: 15
                                color: Colors.textOnPrimary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Reply"
                                role: "label"
                                color: Colors.textOnPrimary
                            }
                        }
                    }

                    Repeater {
                        model: root.buttons

                        MouseArea {
                            id: button
                            required property var modelData
                            required property int index
                            readonly property bool first: index === 0 && !root.canReply

                            width: label.implicitWidth + 28
                            height: 30
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.shown) Notifs.invoke(root.shown.key, modelData.identifier)

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: button.first ? Colors.primary : Colors.secondaryContainer
                                scale: button.pressed ? 0.94 : 1
                                Behavior on scale {
                                    NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: button.first ? Colors.textOnPrimary : Colors.textOnSurface
                                    opacity: button.pressed ? Style.pressTint : button.containsMouse ? Style.hoverTint : 0
                                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                                }
                            }

                            StyledText {
                                id: label
                                anchors.centerIn: parent
                                text: button.modelData.text
                                role: "label"
                                color: button.first ? Colors.textOnPrimary : Colors.textOnSecondaryContainer
                            }
                        }
                    }
                }

                // The answer field.
                Item {
                    width: parent.width
                    height: root.replyOpen ? replyField.implicitHeight + 8 : 0
                    clip: true
                    visible: height > 0

                    Behavior on height {
                        NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                    }

                    ReplyField {
                        id: replyField
                        y: 8
                        width: parent.width
                        hint: root.e?.replyHint ?? ""
                        opacity: root.replyOpen ? 1 : 0
                        onSent: text => {
                            if (root.shown)
                                Notifs.reply(root.shown.key, text);
                        }
                        onCancelled: Notifs.replying = ""
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }
                }

                // The right-click menu.
                Item {
                    width: parent.width
                    height: root.menuOpen ? ruleMenu.implicitHeight + 8 : 0
                    clip: true
                    visible: height > 0

                    Behavior on height {
                        NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                    }

                    RuleMenu {
                        id: ruleMenu
                        y: 8
                        width: parent.width
                        app: root.e?.appName || "Notification"
                        opacity: root.menuOpen ? 1 : 0
                        onDone: root.menuOpen = false
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }
                }
            }
        }

        // Time left: a thin line that shrinks toward the middle.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 5
            width: (parent.width - Style.notifIslandRadius * 2) * root.remaining
            height: 2
            radius: 1
            color: Style.alpha(Colors.primary, 0.55)
            visible: root.timeout > 0 && root.revealed
        }
    }
}
