import QtQuick
import qs.common
import qs.services

// The USB drives popup's content (in BarPopupCard, a click on the bar's USB
// item): one row per drive with its name, size and file system, how full it
// is while mounted, and Open / Eject. What's going on with a drive
// ("Ejecting…", "In use: close what's open on it", "Safe to remove") shows
// under its name. Open closes the popup (the folder opens); Eject keeps it
// open, so the row can say how it went (and goes once the drive is off).
//
//      USB drives
//      (⌁)  SANDISK                         (📂) (⏏)
//           32 GB · exFAT · 28.1 GB free
//           ▰▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱
Column {
    id: root

    Item {
        width: parent.width
        height: 26

        StyledText {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "USB drives"
            role: "title"
        }
    }

    StyledText {
        x: 6
        visible: Drives.count === 0
        topPadding: 4
        bottomPadding: 6
        text: "No USB drive plugged in"
        role: "caption"
        color: Colors.textOnSurfaceVariant
    }

    Repeater {
        model: Drives.drives

        Item {
            id: row
            required property var modelData
            readonly property var d: modelData
            readonly property real total: d.used + d.avail
            readonly property string fs: [...new Set(d.parts.map(p => p.fstype))].join(", ")
            readonly property string busyText: d.busy === "ejecting" ? "Ejecting…" : d.busy === "opening" ? "Opening…" : ""
            readonly property string sub: busyText !== "" ? busyText
                : [d.sizeText, fs, d.mounted && total > 0 ? Drives.sizeText(d.avail) + " free" : ""].filter(s => s !== "").join(" · ")

            width: root.width
            height: info.implicitHeight + 16

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: Colors.textOnSurface
                opacity: hover.containsMouse ? Style.hoverTint * 0.6 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }
            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

            // The drive.
            Rectangle {
                id: badge
                x: 6
                y: 8
                width: 32
                height: 32
                radius: 16
                color: Style.alpha(Colors.textOnSurface, 0.1)

                Icon {
                    anchors.centerIn: parent
                    name: row.d.card ? "sd_card" : "usb"
                    size: 18
                    color: Colors.textOnSurface
                }
            }

            Column {
                id: info
                anchors.left: badge.right
                anchors.leftMargin: 10
                anchors.right: buttons.left
                anchors.rightMargin: 6
                y: 8
                spacing: 2

                StyledText {
                    width: parent.width
                    text: row.d.title
                    weight: 650
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    text: row.sub
                    role: "caption"
                    font.features: ({ "tnum": 1 })
                    color: Colors.textOnSurfaceVariant
                    elide: Text.ElideRight
                }
                // How full, while mounted.
                Item {
                    visible: row.d.mounted && row.total > 0
                    width: parent.width
                    height: 10

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Style.alpha(Colors.textOnSurface, 0.14)

                        Rectangle {
                            width: Math.max(height, parent.width * Math.min(1, row.d.used / Math.max(1, row.total)))
                            height: parent.height
                            radius: parent.radius
                            color: row.d.avail / Math.max(1, row.total) < 0.1 ? Colors.error : Colors.primary
                        }
                    }
                }
                StyledText {
                    visible: row.d.note !== "" && row.busyText === ""
                    width: parent.width
                    text: row.d.note
                    role: "caption"
                    weight: 650
                    color: /^In use|^Not safe|Couldn|Not allowed|failed/.test(row.d.note) ? Colors.error : Colors.primary
                    wrapMode: Text.WordWrap
                }
            }

            Row {
                id: buttons
                anchors.right: parent.right
                anchors.rightMargin: 4
                y: 8
                spacing: 2
                enabled: row.d.busy === ""
                opacity: enabled ? 1 : 0.4

                RoundButton {
                    icon: "folder_open"
                    onClicked: {
                        BarPopupState.close();
                        Drives.open(row.d.key);
                    }
                }
                RoundButton {
                    icon: "eject"
                    onClicked: Drives.eject(row.d.key)
                }
            }
        }
    }

    // A round icon button that lights up under the mouse.
    component RoundButton: MouseArea {
        id: button
        property string icon: ""
        width: 32
        height: 32
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colors.textOnSurface
            opacity: button.pressed ? Style.pressTint : button.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Icon {
            anchors.centerIn: parent
            name: button.icon
            size: 19
            color: Colors.textOnSurface
        }
    }
}
