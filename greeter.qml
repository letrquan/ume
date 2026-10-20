//@ pragma Env QT_QPA_PLATFORMTHEME=none
//@ pragma Env QT_QPA_PLATFORMTHEME_QT6=none
//@ pragma Env MINE_SETTINGS=/var/lib/mine-greeter/settings.json
//@ pragma Env MINE_COLORS_JSON=/var/lib/mine-greeter/colors.json
//@ pragma Env MINE_WEATHER_READONLY=1
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import qs.common
import qs.lock
import qs.greeter

// The login screen: a third way into this shell (shell.qml and lock.qml
// never load greeter/). greetd runs it as the `greeter` user inside cage:
//   /etc/greetd/config.toml → /etc/greetd/mine-greeter/run-greeter.sh
// from a copy of this folder in /etc/greetd/mine-greeter (made by
// greeter-install.sh), since the greeter can't read your home folder. The
// wallpaper, colors, your picture and a few settings come from
// /var/lib/mine-greeter (scripts/greeter-sync.sh keeps them up to date).
// The look and logic: greeter/Greeter.qml.
ShellRoot {
    id: shell

    settings.watchFiles: false

    // Fonts the greeter can't find in your home folder (Google Sans Flex,
    // SF Pro Rounded): copies in fonts/ next to this file, loaded before the
    // screen is made so the clock finds them.
    property bool fontsReady: false
    FolderListModel {
        id: fontFiles
        folder: Qt.resolvedUrl("fonts")
        nameFilters: ["*.ttf", "*.otf"]
        showDirs: false
        onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(() => shell.fontsReady = true)
    }
    Instantiator {
        model: fontFiles
        delegate: FontLoader {
            required property url fileUrl
            source: fileUrl
        }
    }
    // No fonts/ folder: FolderListModel never gets ready.
    Timer {
        interval: 600
        running: !shell.fontsReady
        onTriggered: shell.fontsReady = true
    }

    LazyLoader {
        active: shell.fontsReady

        // cage shows one window, full screen.
        FloatingWindow {
            title: "Login"
            color: "black"
            implicitWidth: 1536
            implicitHeight: 960

            Greeter {
                anchors.fill: parent
            }
        }
    }
}
