import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.services
import "../services/netqr.js" as NetQr

// Share the Wi-Fi network you're on (the Wi-Fi page's Share): a QR code a
// phone's camera joins with (WIFI:T:WPA;S:<name>;P:<password>;;), the name,
// and the password (dots until the eye). The password is the one
// NetworkManager saved, read when this opens:
//   nmcli -t -e no -f UUID,TYPE,DEVICE,NAME connection show --active      which profile
//   nmcli -t -e no -s -f 802-11-wireless.ssid,…  connection show uuid <it>   its name and password
// (-s hands out secrets; NetworkManager may first ask for your password
// through the shell's own password dialog.) It lives only in this view and
// is gone when it closes: never logged, never in a file (control/QrCode.qml
// draws the code itself).
// MINE_NMCLI: the nmcli to run (tests).
Column {
    id: root

    signal done()

    // reading | ready | nopass (no saved password) | enterprise | none (not
    // on a Wi-Fi network) | failed
    property string phase: "reading"
    property string why: ""
    property string ssid: ""
    property string kind: ""            // WPA | WEP | nopass
    property string password: ""
    property bool hidden: false
    property bool showPassword: false
    readonly property string qrText: phase === "ready" ? NetQr.wifiText(ssid, kind, password, hidden) : ""
    readonly property string nmcli: Quickshell.env("MINE_NMCLI") || "nmcli"

    spacing: 12

    Component.onCompleted: active.running = true
    Component.onDestruction: {
        password = "";
        secrets.done = true;
    }

    // Which profile is on the Wi-Fi card.
    Process {
        id: active
        command: ["sh", "-c", 'exec "$@"', "sh", root.nmcli, "-t", "-e", "no", "-f", "UUID,TYPE,DEVICE,NAME", "connection", "show", "--active"]
        stdout: StdioCollector {
            onStreamFinished: {
                const wifi = NetQr.rows(text, 4).filter(r => r[1] === "802-11-wireless");
                const dev = ControlState.wifiDevice?.name ?? "";
                const it = wifi.find(r => r[2] === dev) ?? wifi[0];
                if (!it) {
                    root.phase = "none";
                    return;
                }
                secrets.command = ["sh", "-c", 'exec "$@"', "sh", root.nmcli, "-t", "-e", "no", "-s", "-f",
                    "802-11-wireless.ssid,802-11-wireless.mode,802-11-wireless.hidden,802-11-wireless-security.key-mgmt,802-11-wireless-security.psk,802-11-wireless-security.wep-key0",
                    "connection", "show", "uuid", it[0]];
                secrets.running = true;
            }
        }
    }

    // Its name and password.
    Process {
        id: secrets
        property bool done: false
        stdout: StdioCollector {
            id: secretOut
            onStreamFinished: {
                if (secrets.done)
                    return;
                const f = NetQr.fields(text);
                const mode = f["802-11-wireless.mode"] ?? "";
                const keyMgmt = f["802-11-wireless-security.key-mgmt"] ?? "";
                const psk = f["802-11-wireless-security.psk"] ?? "";
                const wep = f["802-11-wireless-security.wep-key0"] ?? "";
                root.ssid = f["802-11-wireless.ssid"] ?? "";
                root.hidden = (f["802-11-wireless.hidden"] ?? "") === "yes";
                root.kind = NetQr.kind(keyMgmt, wep);
                if (root.ssid === "") {
                    root.phase = "failed";
                    root.why = "NetworkManager didn't say";
                } else if (mode === "ap") {
                    root.phase = "failed";
                    root.why = "This is the hotspot: its own page has the code";
                } else if (root.kind === "") {
                    root.phase = "enterprise";
                } else if (root.kind === "nopass") {
                    root.phase = "ready";
                } else {
                    root.password = root.kind === "WEP" ? wep : psk;
                    root.phase = root.password !== "" ? "ready" : "nopass";
                }
            }
        }
        stderr: StdioCollector { id: secretErr }
    }

    // The code, or why there isn't one.
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 216
        height: 216

        QrCode {
            anchors.fill: parent
            visible: root.phase === "ready"
            text: root.qrText
        }

        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: 10
            visible: root.phase !== "ready"

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: root.phase === "reading" ? "hourglass_top" : root.phase === "enterprise" ? "badge" : "key_off"
                size: 40
                fill: 0
                color: Colors.textOnSurfaceVariant
            }
            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Colors.textOnSurfaceVariant
                text: root.phase === "reading" ? "Getting the password…"
                    : root.phase === "nopass" ? "No saved password for this network (another app keeps it, or it was never saved)"
                    : root.phase === "enterprise" ? "This network signs in with a user name (802.1X): a code can't carry that"
                    : root.phase === "none" ? "Not on a Wi-Fi network"
                    : root.why
            }
        }
    }

    StyledText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.ssid
        visible: text !== ""
        role: "title"
        elide: Text.ElideRight
    }
    StyledText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        visible: root.phase === "ready"
        text: "Point a phone's camera at the code to join"
        role: "caption"
        color: Colors.textOnSurfaceVariant
    }

    // The password, dots until the eye.
    Rectangle {
        width: parent.width
        height: 44
        radius: Style.inner(Style.ccRadius, Style.ccPadding)
        color: Style.alpha(Colors.textOnSurface, 0.08)
        visible: root.phase === "ready"

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
            text: root.kind === "nopass" ? "None (open network)"
                : root.showPassword ? root.password : "•".repeat(Math.min(12, Math.max(8, root.password.length)))
            weight: 600
        }
        Clickable {
            id: eye
            anchors.right: parent.right
            anchors.rightMargin: 4
            visible: root.kind !== "nopass"
            onClicked: root.showPassword = !root.showPassword
            Icon { name: root.showPassword ? "visibility_off" : "visibility"; size: 18 }
        }
    }

    Item {
        width: parent.width
        height: 36

        Clickable {
            anchors.right: parent.right
            implicitHeight: 34
            padding: 14
            onClicked: root.done()
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Done"
                weight: 650
                color: Colors.primary
            }
        }
    }
}
