import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// System info, fetch style: the distro logo, user@host and a few rows.
// Read once when the lock starts (uptime every minute).
LockCard {
    id: root

    property string packages: ""
    property string uptime: ""

    FileView { id: hostFile; path: "/etc/hostname"; blockLoading: true }
    FileView { id: osFile; path: "/etc/os-release"; blockLoading: true }
    FileView { id: kernelFile; path: "/proc/sys/kernel/osrelease"; blockLoading: true }
    FileView { id: uptimeFile; path: "/proc/uptime" }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            uptimeFile.reload();
            const up = Math.floor(Number(uptimeFile.text().split(" ")[0]) || 0);
            const d = Math.floor(up / 86400), h = Math.floor(up % 86400 / 3600), m = Math.floor(up % 3600 / 60);
            root.uptime = (d > 0 ? d + "d " : "") + (h > 0 ? h + "h " : "") + m + "m";
        }
    }
    // Your login shell (the passwd entry), not $SHELL of whatever started
    // the lock (a terminal running another shell, for one).
    property string loginShell: (Quickshell.env("SHELL") ?? "").split("/").pop()
    Process {
        running: true
        command: ["getent", "passwd", Quickshell.env("USER") ?? ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const sh = (text.trim().split(":")[6] ?? "").split("/").pop();
                if (sh !== "")
                    root.loginShell = sh;
            }
        }
    }
    Process {
        running: true
        command: ["sh", "-c", "pacman -Qq 2>/dev/null | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: root.packages = text.trim() + " (pacman)"
        }
    }

    Row {
        id: head
        spacing: 12

        Image {
            width: 44
            height: 44
            source: "file:///usr/share/icons/hicolor/scalable/apps/org.cachyos.hello.svg"
            sourceSize: Qt.size(88, 88)
            fillMode: Image.PreserveAspectFit
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: (Quickshell.env("USER") ?? "") + "@" + hostFile.text().trim()
                role: "title"
                color: Colors.primary
            }
            StyledText {
                text: osFile.text().match(/^PRETTY_NAME="?([^"\n]*)/m)?.[1] ?? "Linux"
                role: "body"
                color: Colors.textOnSurfaceVariant
            }
        }
    }

    Column {
        anchors.top: head.bottom
        anchors.topMargin: 10
        width: parent.width
        spacing: 4

        Repeater {
            model: [
                { icon: "memory_alt", key: "Kernel", value: kernelFile.text().trim() },
                { icon: "schedule", key: "Uptime", value: root.uptime },
                { icon: "grid_view", key: "WM", value: "mango + mine" },
                { icon: "terminal", key: "Shell", value: root.loginShell },
                { icon: "package_2", key: "Packages", value: root.packages }
            ]

            Row {
                required property var modelData
                width: parent.width
                spacing: 8

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: parent.modelData.icon
                    size: 16
                    color: Colors.tertiary
                }
                StyledText {
                    width: 64
                    text: parent.modelData.key
                    color: Colors.textOnSurfaceVariant
                }
                StyledText {
                    width: parent.width - 96
                    text: parent.modelData.value
                    weight: 550
                    elide: Text.ElideRight
                }
            }
        }
    }
}
