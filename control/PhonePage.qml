import QtQuick
import qs.common
import qs.services

// Your phone (KDE Connect): its battery up top, then ring it, send it files
// or the clipboard, ping it; other phones and tablets nearby to pair (or
// one asking to pair) under that.
//
// Pairing takes two clicks, so a stray one can't let a device in: the first
// opens the row, the second (Pair, Accept) does it. A request comes with a
// key that kdeconnectd makes from both devices' certificates and the
// request's time; your phone shows the same one, and a device that only
// borrowed your phone's name can't. A request it sends shows its key here;
// one you send shows its key as soon as it's sent (not before: the time is
// part of it), for you to compare on the phone.
Column {
    id: root

    spacing: 6

    readonly property var device: Phone.device

    Component.onCompleted: Phone.use(true)
    Component.onDestruction: Phone.use(false)

    // While a pairing goes on, look every 2 s (a request lasts 30 s).
    Timer {
        running: Phone.pairing
        interval: 2000
        repeat: true
        onTriggered: Phone.refresh()
    }

    // The row opened for pairing, and what it showed: if the device's state
    // or key changes, it closes again and you look again.
    property var opened: ({ id: "", state: "", key: "" })

    function stateOf(d) {
        return d.paired ? "paired" : d.pairRequestedByPeer ? "asking" : d.pairRequested ? "asked" : "none";
    }
    function isOpen(d) {
        return opened.id === d.id && opened.state === stateOf(d) && opened.key === d.key;
    }
    function toggle(d) {
        opened = isOpen(d) ? { id: "", state: "", key: "" } : { id: d.id, state: stateOf(d), key: d.key };
        Phone.refresh();
    }
    function closeRow() {
        opened = { id: "", state: "", key: "" };
    }
    // "1A2B3C4D" → "1A2B 3C4D", easier to compare.
    function spaced(key) {
        return key.slice(0, 4) + " " + key.slice(4);
    }

    PageHeader {
        width: parent.width
        title: root.device?.name ?? "Phone"

        Clickable {
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: 32
            onClicked: Phone.refresh()
            Icon { name: "refresh"; size: 18 }
        }
    }

    // ---- The phone itself --------------------------------------------------------------
    Item {
        width: parent.width
        height: 64
        visible: root.device !== null

        Item {
            id: badge
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: 48

            Shape {
                anchors.fill: parent
                shape: Phone.connected ? "Cookie9Sided" : "Circle"
                color: Phone.connected ? Colors.primaryContainer : Style.alpha(Colors.textOnSurface, 0.1)
                rotation: Phone.connected ? 0 : -40
                Behavior on rotation {
                    NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                }
            }
            Icon {
                anchors.centerIn: parent
                name: Phone.glyphFor(root.device)
                size: 24
                fill: Phone.connected ? 1 : 0
                color: Phone.connected ? Colors.textOnPrimaryContainer : Colors.textOnSurfaceVariant
            }
        }

        Column {
            anchors.left: badge.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Row {
                spacing: 6
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Phone.charge >= 0
                    text: Phone.charge + "%"
                    role: "headline"
                    font.features: ({ "tnum": 1 })
                    color: Phone.low ? Colors.error : Colors.textOnSurface
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Phone.charging
                    name: "bolt"
                    size: 18
                    color: Colors.primary
                }
            }
            StyledText {
                width: parent.width
                text: !Phone.connected ? "Not connected · open KDE Connect on the phone"
                    : Phone.charging ? "Charging" : Phone.charge >= 0 ? "Connected" : "Connected · no battery info"
                role: "caption"
                color: Colors.textOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }

    // ---- What you can do ---------------------------------------------------------------
    Column {
        width: parent.width
        spacing: 2
        visible: root.device !== null
        opacity: Phone.connected ? 1 : 0.4
        enabled: Phone.connected

        Behavior on opacity {
            NumberAnimation { duration: Motion.normal }
        }

        ListItem {
            width: parent.width
            icon: "vibration"
            label: "Ring my phone"
            detail: Phone.done === "ring" ? "Ringing…" : "Rings even when it's on silent"
            onClicked: Phone.ring()
        }
        ListItem {
            width: parent.width
            icon: "upload_file"
            label: "Send files"
            detail: Phone.pickerError !== "" ? Phone.pickerError : Phone.done === "files" ? "Sent" : "Pick them, they land in the phone's Downloads"
            onClicked: Phone.sendFiles()
        }
        ListItem {
            width: parent.width
            icon: "content_paste_go"
            label: "Send the clipboard"
            detail: Phone.done === "clipboard" ? "Sent" : "What you copied last, to paste on the phone"
            onClicked: Phone.sendClipboard()
        }
        ListItem {
            width: parent.width
            icon: "notifications_active"
            label: "Ping"
            detail: Phone.done === "ping" ? "Sent" : "A notification on the phone"
            onClicked: Phone.ping()
        }
    }

    // ---- Others nearby: pair -------------------------------------------------------------
    StyledText {
        x: 8
        visible: Phone.others.length > 0
        text: root.device === null ? "Phones nearby" : "Other devices"
        role: "label"
        color: Colors.textOnSurfaceVariant
    }
    Repeater {
        model: Phone.others

        ListItem {
            id: row
            required property var modelData
            readonly property var d: modelData
            readonly property string state_: root.stateOf(d)
            // Ours waiting: always open, its key is the point.
            readonly property bool open: state_ === "asked" || (state_ !== "paired" && root.isOpen(d))
            readonly property string note: Phone.pairNote.id === d.id ? Phone.pairNote.text : ""

            width: root.width
            icon: Phone.glyphFor(d)
            label: d.name
            detail: note !== "" ? note
                  : state_ === "paired" ? (d.reachable ? "Paired · connected" : "Paired · not connected")
                  : state_ === "asking" ? (open ? "Wants to pair · compare the key" : "Wants to pair · click to see its key")
                  : state_ === "asked" ? "You asked to pair · waiting for it"
                  : "Not paired · click to pair"
            busy: state_ === "asked"
            trailing: state_ === "asking" ? "key" : state_ === "none" ? "link" : ""
            // Paired ones only say so (unpair in KDE Connect's own app).
            enabled: state_ !== "paired"
            cursorShape: state_ === "paired" ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: if (state_ === "asking" || state_ === "none") root.toggle(d)

            // The second step.
            Item {
                width: row.width
                height: row.open ? box.height + 8 : 0
                visible: height > 0
                clip: true

                Rectangle {
                    id: box
                    x: 52
                    y: 2
                    width: parent.width - 52 - 10
                    height: steps.implicitHeight
                    radius: 16
                    color: Style.alpha(Colors.textOnSurface, 0.06)

                    // Clicks in here stay here (not a click on the row).
                    MouseArea {
                        anchors.fill: parent
                    }

                    Column {
                        id: steps
                        width: parent.width
                        padding: 12
                        spacing: 6

                        // The key, big: while either side asks.
                        Row {
                            visible: row.state_ !== "none" && row.d.key !== ""
                            spacing: 8

                            StyledText {
                                anchors.baseline: keyText.baseline
                                text: "Key"
                                role: "label"
                                color: Colors.textOnSurfaceVariant
                            }
                            StyledText {
                                id: keyText
                                text: root.spaced(row.d.key)
                                role: "headline"
                                font.features: ({ "tnum": 1 })
                                font.letterSpacing: 1
                                color: Colors.primary
                            }
                        }
                        StyledText {
                            width: parent.width - 24
                            wrapMode: Text.Wrap
                            role: "caption"
                            color: Colors.textOnSurfaceVariant
                            text: row.state_ === "asking"
                                ? (row.d.key !== "" ? "Accept only if your phone shows this same key. Didn't ask to pair from it? Reject."
                                    : "KDE Connect gave no key to compare, so it can't be accepted here. Reject, and pair from your phone again.")
                                : row.state_ === "asked"
                                ? (row.d.key !== "" ? "Now on your phone: accept only if it shows this same key."
                                    : "Waiting for your phone to accept.")
                                : "Pairing lets it get your clipboard and send you files. Next, a key shows here and on it: they must match."
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            spacing: 4

                            PairButton {
                                visible: row.state_ === "asking"
                                text: "Reject"
                                onClicked: { Phone.rejectPairing(row.d); root.closeRow(); }
                            }
                            PairButton {
                                visible: row.state_ === "asking" && row.d.key !== ""
                                text: "Accept"
                                filled: true
                                onClicked: Phone.acceptPairing(row.d, root.opened.key)
                            }
                            PairButton {
                                visible: row.state_ === "none"
                                text: "Not now"
                                onClicked: root.closeRow()
                            }
                            PairButton {
                                visible: row.state_ === "none"
                                text: "Pair"
                                filled: true
                                onClicked: { Phone.pair(row.d); root.closeRow(); }
                            }
                            PairButton {
                                visible: row.state_ === "asked"
                                text: "Cancel"
                                onClicked: Phone.cancelPairing(row.d)
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Nothing to show yet -----------------------------------------------------------------
    EmptyState {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.device === null && Phone.others.length === 0
        textWidth: parent.width - 32
        icon: !Phone.known ? "hourglass_empty" : Phone.installed && Phone.running ? "smartphone" : "mobile_off"
        title: !Phone.known ? "Looking…"
            : !Phone.installed ? "KDE Connect isn't installed"
            : !Phone.running ? "KDE Connect isn't running"
            : "No phone yet"
        hint: !Phone.known ? ""
            : !Phone.installed ? "sudo pacman -S kdeconnect, then open ports 1714–1764 in ufw"
            : !Phone.running ? "Start kdeconnectd"
            : "Install KDE Connect on the phone, on the same Wi-Fi, and it shows up here to pair"
    }

    // A pill button: the main one filled (like the password dialog's).
    component PairButton: MouseArea {
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
