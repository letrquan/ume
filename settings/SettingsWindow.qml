import QtQuick
import Quickshell
import qs.common
import qs.services

// The Settings window: an ordinary app window (mango tiles or floats it like
// any other). shell.qml creates it only while SettingsState.open; closing it
// any way (its close key, Esc) unloads it. See-through: mango blurs what's
// behind it and SettingsView tints it (Style.settingsOpacity).
FloatingWindow {
    id: root

    title: "Shell Settings"
    implicitWidth: 900
    implicitHeight: 620
    minimumSize: Qt.size(720, 480)
    color: "transparent"

    // Once the shell has closed it (it may open again right away, at a
    // setting from the launcher), this window going away says nothing more.
    property bool leaving: false
    Connections {
        target: SettingsState
        function onOpenChanged() {
            if (!SettingsState.open)
                root.leaving = true;
        }
    }

    onClosed: if (!leaving) SettingsState.close()
    onVisibleChanged: if (!visible && !leaving) SettingsState.close()

    SettingsView {
        anchors.fill: parent
        onCloseRequested: SettingsState.close()
    }
}
