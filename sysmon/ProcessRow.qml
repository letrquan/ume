import QtQuick
import Quickshell
import qs.common
import qs.services

// One of the busiest apps: [icon] Name ×n        1.4%   987M  (✕)
// (×n: that many processes of the same program, added up.) The ✕ shows
// on hover, only on your own apps, and asks first: it turns into a red
// "End", and a second click ends the app (SIGTERM to each of its
// processes, like closing it). The rows stay; only what's in them changes
// every couple of seconds, and a question goes away as soon as its row
// shows another app.
MouseArea {
    id: root

    // { pids, user, name, count, cpu, mem } (SysStats.processes), or null
    property var proc: null
    // Its app (desktop entry), if it has one: the icon; and the name shown.
    property var entry: null
    property string name: ""
    property string sortBy: "cpu"
    property real cpuColumn: 52
    property real memColumn: 52
    property real endColumn: 28

    // top cuts long user names to 8 letters with a "+".
    readonly property string me: Quickshell.env("USER") ?? ""
    readonly property bool mine: proc !== null && (proc.user === me
        || (proc.user.endsWith("+") && me.startsWith(proc.user.slice(0, -1))))
    readonly property int count: proc?.count ?? 1
    // The app the red "End" is for (by name).
    property string asking: ""
    readonly property bool askingHere: asking !== "" && asking === proc?.name

    implicitHeight: 32
    hoverEnabled: true

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Colors.textOnSurface
        opacity: root.containsMouse && root.proc ? Style.hoverTint : 0
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
        // No app: a soft round chip with a glyph, about the size of an icon.
        Rectangle {
            anchors.fill: parent
            visible: root.entry === null && root.proc !== null
            radius: width / 2
            color: Style.alpha(Colors.textOnSurface, 0.08)

            Icon {
                anchors.centerIn: parent
                name: root.proc?.user === "root" ? "settings" : "terminal"
                size: 14
                color: Colors.textOnSurfaceVariant
            }
        }
    }

    Row {
        anchors.left: iconBox.right
        anchors.leftMargin: 10
        anchors.right: cpuText.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - (times.visible ? times.width + parent.spacing : 0))
            text: root.name
            elide: Text.ElideRight
        }
        StyledText {
            id: times
            anchors.verticalCenter: parent.verticalCenter
            visible: root.count > 1
            text: "×" + root.count
            role: "caption"
            font.features: ({ "tnum": 1 })
            color: Style.alpha(Colors.textOnSurfaceVariant, 0.8)
        }
    }

    // ---- numbers ----------------------------------------------------------------------
    StyledText {
        id: cpuText
        anchors.right: memText.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.cpuColumn
        horizontalAlignment: Text.AlignRight
        text: root.proc ? (root.proc.cpu >= 10 ? Math.round(root.proc.cpu) : root.proc.cpu.toFixed(1)) + "%" : ""
        font.features: ({ "tnum": 1 })
        color: root.sortBy === "cpu" ? Colors.textOnSurface : Colors.textOnSurfaceVariant
    }
    StyledText {
        id: memText
        anchors.right: parent.right
        anchors.rightMargin: root.endColumn
        anchors.verticalCenter: parent.verticalCenter
        width: root.memColumn
        horizontalAlignment: Text.AlignRight
        text: root.proc ? SysStats.shortSize(root.proc.mem) : ""
        font.features: ({ "tnum": 1 })
        color: root.sortBy === "memory" ? Colors.textOnSurface : Colors.textOnSurfaceVariant
    }

    // ---- end it: ✕ on hover, then a red "End" over the numbers ------------------------
    MouseArea {
        id: endButton
        anchors.right: parent.right
        anchors.rightMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        width: root.askingHere ? endText.implicitWidth + 24 : 22
        height: 22
        visible: root.mine && (root.containsMouse || root.askingHere)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.askingHere) {
                SysStats.endProcesses(root.proc.pids);
                root.asking = "";
            } else {
                root.asking = root.proc?.name ?? "";
                forget.restart();
            }
        }

        Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial } }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.askingHere ? Colors.error : Colors.textOnSurface
            opacity: root.askingHere ? 1 : endButton.containsMouse ? Style.pressTint : 0
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
        Icon {
            anchors.centerIn: parent
            visible: !root.askingHere
            name: "close"
            size: 14
            color: endButton.containsMouse ? Colors.error : Colors.textOnSurfaceVariant
        }
        StyledText {
            id: endText
            anchors.centerIn: parent
            visible: root.askingHere
            text: root.count > 1 ? "End all" : "End"
            role: "label"
            color: Colors.textOnError
        }
    }

    // The question goes away on its own, or when the row shows another app.
    Timer {
        id: forget
        interval: 3500
        onTriggered: root.asking = ""
    }
    onProcChanged: if (asking !== "" && proc?.name !== asking) asking = ""
}
