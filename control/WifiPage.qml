import QtQuick
import Quickshell.Networking
import qs.common
import qs.services

// Wi-Fi networks: the connected one first, then known ones, then by signal.
// Click a network to connect (a password field opens for new secured ones),
// click the connected one to disconnect.
Column {
    id: root

    spacing: 6

    // Which network has its password field open ("" = none).
    property string asking: ""
    readonly property var networks: {
        const list = ControlState.wifiDevice?.networks.values ?? [];
        return list.filter(n => n.name !== "").sort((a, b) =>
            (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength));
    }

    // Look for networks while this page is open.
    Component.onCompleted: ControlState.setScanning(true)
    Component.onDestruction: ControlState.setScanning(false)

    function signalIcon(n) {
        const s = n.signalStrength;
        return s > 0.75 ? "signal_wifi_4_bar" : s > 0.5 ? "network_wifi_3_bar" : s > 0.25 ? "network_wifi_2_bar" : "network_wifi_1_bar";
    }
    function secured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }

    PageHeader {
        width: parent.width
        title: "Wi-Fi"
        hasSwitch: true
        checked: Networking.wifiEnabled
        onFlipped: ControlState.setWifi(!Networking.wifiEnabled)
    }

    StyledText {
        width: parent.width
        visible: !Networking.wifiEnabled || root.networks.length === 0
        topPadding: 18
        bottomPadding: 18
        horizontalAlignment: Text.AlignHCenter
        text: !Networking.wifiEnabled ? "Wi-Fi is off" : "Looking for networks…"
        color: Colors.textOnSurfaceVariant
    }

    Flickable {
        width: parent.width
        height: Math.min(contentHeight, 6 * 50)
        visible: Networking.wifiEnabled && root.networks.length > 0
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: parent.width
            spacing: 2

            Repeater {
                model: root.networks

                ListItem {
                    id: row
                    required property var modelData
                    readonly property var n: modelData
                    property string failed: ""

                    width: list.width
                    icon: root.signalIcon(n)
                    label: n.name
                    detail: n.connected ? "Connected"
                          : n.stateChanging ? "Connecting…"
                          : failed !== "" ? failed
                          : n.known ? "Saved" : ""
                    trailing: root.secured(n) ? "lock" : ""
                    current: n.connected
                    busy: n.stateChanging

                    onClicked: {
                        if (n.connected)
                            ControlState.disconnectNetwork(n);
                        else if (n.known || !root.secured(n))
                            ControlState.connectNetwork(n, "");
                        else
                            root.asking = root.asking === n.name ? "" : n.name;
                    }

                    Connections {
                        target: row.n
                        function onConnectionFailed(reason) {
                            row.failed = "Couldn't connect";
                            if (root.secured(row.n))
                                root.asking = row.n.name;
                        }
                    }

                    // Password for a new secured network.
                    Item {
                        width: row.width
                        height: root.asking === row.n.name ? 50 : 0
                        visible: height > 0
                        clip: true

                        Rectangle {
                            x: 52
                            y: 4
                            width: parent.width - 52 - 10
                            height: 38
                            radius: 19
                            color: Style.alpha(Colors.textOnSurface, 0.08)
                            border.width: 1
                            border.color: password.activeFocus ? Colors.primary : "transparent"

                            TextInput {
                                id: password
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.right: go.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                echoMode: TextInput.Password
                                color: Colors.textOnSurface
                                font.family: Style.font
                                font.pixelSize: Style.textSize("body")
                                clip: true
                                focus: root.asking === row.n.name
                                onVisibleChanged: if (visible) forceActiveFocus()
                                onAccepted: go.clicked(null)

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Password"
                                    color: Colors.textOnSurfaceVariant
                                    visible: password.text === ""
                                }
                            }

                            Clickable {
                                id: go
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                implicitHeight: 30
                                padding: 12
                                onClicked: {
                                    if (password.text === "")
                                        return;
                                    row.failed = "";
                                    ControlState.connectNetwork(row.n, password.text);
                                    password.text = "";
                                    root.asking = "";
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Join"
                                    weight: 650
                                    color: Colors.primary
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
