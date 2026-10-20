import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// "While you were away": which apps sent notifications since the lock
// started, and how many, as one line under the time:
//        (✈) Telegram 5  ·  (m) Messenger 2  ·  +1
// Names off (Style.lockNotifNames): the icons and "7 notifications".
// Never what they say: only each one's app, icon and time are read. A
// repeat of one from before the lock (a phone resends what's unread when it
// reconnects) isn't new: it counts by when it first came (`first`).
//
// The shell keeps the list (services/Notifs.qml saves it); the lock is a
// separate process, so this reads the saved file and watches it. A file
// that's missing, empty, broken or far too big shows nothing; nothing here
// can stop the lock from working.
Item {
    id: root

    property date lockedAt: new Date()
    // White on the wallpaper (mac style), or the theme's text (panel).
    property color textColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.72)

    // [{ app, icon, count, last }], most first.
    property var apps: []
    readonly property int total: apps.reduce((sum, a) => sum + a.count, 0)
    readonly property bool wanted: Style.lockNotifCounts && total > 0
    readonly property bool names: Style.lockNotifNames
    // How many apps get a place on the line; the rest is "+n".
    readonly property int maxShown: names ? 4 : 6
    readonly property var shown: apps.slice(0, maxShown)

    // MINE_NOTIF_HISTORY: another file, as for the shell (tests).
    readonly property string path: Quickshell.env("MINE_NOTIF_HISTORY")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/notifications.json")
    // Far more than the shell ever writes (500 long ones are ~1 MB).
    readonly property int maxLength: 4 * 1024 * 1024

    implicitWidth: line.implicitWidth
    implicitHeight: 24

    FileView {
        id: file
        path: Style.lockNotifCounts ? root.path : ""
        watchChanges: true
        printErrors: false

        onLoaded: root.read(text())
        onLoadFailed: root.apps = []
        onFileChanged: reload()
    }
    onLockedAtChanged: if (Style.lockNotifCounts) file.reload()

    function read(text) {
        try {
            apps = count(text);
        } catch (e) {
            apps = [];
        }
    }

    function count(text) {
        if (typeof text !== "string" || text.length === 0 || text.length > maxLength)
            return [];
        const data = JSON.parse(text);
        const list = Array.isArray(data?.list) ? data.list : [];
        const since = lockedAt.getTime();
        // (Without a prototype: an app may be called "constructor".)
        const at = Object.create(null), out = [];
        for (const e of list.slice(0, 1000)) {
            const came = typeof e?.first === "number" ? e.first : e?.time;
            if (!e || typeof e !== "object" || typeof came !== "number" || !(came >= since))
                continue;
            const app = typeof e.appName === "string" && e.appName.trim() !== "" ? e.appName.trim().substring(0, 40) : "Notification";
            if (at[app] === undefined) {
                at[app] = out.length;
                out.push({ app: app, icon: iconOf(e.icon), count: 0, last: came });
            }
            const a = out[at[app]];
            a.count++;
            a.last = Math.max(a.last, came);
        }
        return out.sort((a, b) => b.count - a.count || b.last - a.last);
    }

    // Only an app's icon: a theme icon, or a file in an icon folder (never a
    // picture that came with a notification, nor anything from the network).
    function iconOf(icon) {
        if (typeof icon !== "string" || icon.length > 300 || icon.includes(".."))
            return "";
        if (/^image:\/\/icon\/[A-Za-z0-9._-]+$/.test(icon))
            return icon;
        const home = Quickshell.env("HOME");
        for (const dir of ["/usr/share/icons/", "/usr/share/pixmaps/", home + "/.local/share/icons/"]) {
            if (icon.startsWith("file://" + dir))
                return icon;
        }
        return "";
    }

    Row {
        id: line
        anchors.centerIn: parent
        spacing: root.names ? 14 : 8

        Repeater {
            model: root.shown

            Row {
                id: app
                required property var modelData
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // A dot between apps (names on).
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.names && app.index > 0
                    rightPadding: 8
                    text: "·"
                    color: root.dimColor
                    weight: 700
                }

                // The app's icon on its tile, or its first letter.
                AppIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 20
                    source: app.modelData.icon
                    name: app.modelData.app
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.names
                    width: Math.min(implicitWidth, 160)
                    text: app.modelData.app
                    color: root.textColor
                    weight: 600
                    elide: Text.ElideRight
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.names
                    text: app.modelData.count
                    color: root.dimColor
                    weight: 650
                }
            }
        }

        // More apps than fit.
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.apps.length > root.shown.length
            text: (root.names ? "·  " : "") + "+" + (root.apps.length - root.shown.length)
            color: root.dimColor
            weight: 650
        }

        // Names off: how many in all.
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.names
            leftPadding: 2
            text: root.total + (root.total === 1 ? " notification" : " notifications")
            color: root.textColor
            weight: 600
        }
    }
}
