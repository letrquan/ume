import QtQuick
import qs.common
import qs.services

// The hotspot (services/Hotspot.qml): the switch, what turning it on does,
// and while it's on its name, password (dots until the eye) and a QR code
// phones join with. The password is read when this opens and forgotten
// when it closes.
Column {
    id: root

    spacing: 10

    property bool showPassword: false

    Component.onCompleted: {
        Hotspot.use(true);
        Hotspot.reveal();
    }
    Component.onDestruction: {
        Hotspot.conceal();
        Hotspot.use(false);
    }

    PageHeader {
        width: parent.width
        title: "Hotspot"
        hasSwitch: true
        checked: Hotspot.busy === "on" || (Hotspot.on && Hotspot.busy !== "off")
        onFlipped: Hotspot.tap()
    }

    // Off: what happens.
    Column {
        width: parent.width
        spacing: 8
        visible: !Hotspot.on && Hotspot.busy === ""

        Rectangle {
            width: parent.width
            height: warn.implicitHeight + 24
            radius: Style.inner(Style.ccRadius, Style.ccPadding)
            color: Hotspot.armed ? Style.alpha(Colors.primary, 0.16) : Style.alpha(Colors.textOnSurface, 0.08)

            StyledText {
                id: warn
                x: 14
                y: 12
                width: parent.width - 28
                wrapMode: Text.WordWrap
                color: Colors.textOnSurface
                text: (Hotspot.leaving !== ""
                        ? "Turning it on leaves " + Hotspot.leaving + " (the Wi-Fi card can't be on a network and be a hotspot at once); turning it off joins it again."
                        : "Other devices join a Wi-Fi network this laptop makes.")
                    + (ControlState.wiredDevice ? "\n\nDevices on it share your cable's internet."
                        : "\n\nWithout a cable, devices on it get no internet through it: good for sharing files nearby.")
                    + (Hotspot.armed ? "\n\nClick again to turn it on." : "")
            }
        }

        StyledText {
            width: parent.width
            visible: Hotspot.error !== "" || (Hotspot.known && Hotspot.device === "")
            wrapMode: Text.WordWrap
            text: Hotspot.error !== "" ? Hotspot.error : "No Wi-Fi card"
            role: "caption"
            color: Colors.error
        }
    }

    StyledText {
        width: parent.width
        visible: Hotspot.busy !== ""
        topPadding: 18
        bottomPadding: 18
        horizontalAlignment: Text.AlignHCenter
        text: Hotspot.busy === "on" ? "Turning on…" : "Turning off" + (Hotspot.previousName !== "" ? ", back to " + Hotspot.previousName : "") + "…"
        color: Colors.textOnSurfaceVariant
    }

    // On: the code, the name, the password.
    Column {
        width: parent.width
        spacing: 12
        visible: Hotspot.on && Hotspot.busy === ""

        QrCode {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 216
            height: 216
            visible: Hotspot.qrText !== ""
            text: Hotspot.qrText
        }
        StyledText {
            width: parent.width
            visible: Hotspot.qrText === ""
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: Hotspot.secretError !== "" ? Hotspot.secretError : "Getting the password…"
            color: Colors.textOnSurfaceVariant
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: Hotspot.qrText !== ""
            text: "Point a phone's camera at the code to join"
            role: "caption"
            color: Colors.textOnSurfaceVariant
        }

        Rectangle {
            width: parent.width
            height: 88
            radius: Style.inner(Style.ccRadius, Style.ccPadding)
            color: Style.alpha(Colors.textOnSurface, 0.08)

            Column {
                anchors.fill: parent

                Item {
                    width: parent.width
                    height: 44

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Name"
                        color: Colors.textOnSurfaceVariant
                    }
                    StyledText {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - 110)
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: Hotspot.ssid
                        weight: 600
                    }
                }
                Item {
                    width: parent.width
                    height: 44

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Password"
                        color: Colors.textOnSurfaceVariant
                    }
                    StyledText {
                        anchors.right: eye.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - 140)
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                        text: Hotspot.password === "" ? "…" : root.showPassword ? Hotspot.password : "•".repeat(Math.min(12, Math.max(8, Hotspot.password.length)))
                        weight: 600
                    }
                    Clickable {
                        id: eye
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        onClicked: root.showPassword = !root.showPassword
                        Icon { name: root.showPassword ? "visibility_off" : "visibility"; size: 18 }
                    }
                }
            }
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            text: (ControlState.wiredDevice ? "Devices on it share your cable's internet." : "No cable connected: devices on it get no internet through it.")
                + (Hotspot.previousName !== "" ? " Off brings back " + Hotspot.previousName + "." : "")
            role: "caption"
            color: Colors.textOnSurfaceVariant
        }
    }
}
