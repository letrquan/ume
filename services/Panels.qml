pragma Singleton
import QtQuick
import Quickshell

// Opens the settings.
Singleton {
    // The Settings window (Super+, / ⚙ in the control center).
    function settings() {
        SettingsState.show();
    }

    // The keyboard shortcut cheat sheet (Super+/).
    function cheatsheet() {
        CheatSheetState.toggle();
    }

    // The overview (Super+O, the hot corner).
    function overview() {
        OverviewState.toggle();
    }

    // The System popup (click a stat on the bar).
    function sysmon() {
        SysmonState.toggle();
    }

    // Style.qml itself, in your text editor (micro), in a terminal. Saving
    // it changes the shell right away.
    function editStyle() {
        Quickshell.execDetached(["xdg-terminal-exec", "micro", Quickshell.shellDir + "/common/Style.qml"]);
    }

    // toggle("session"), toggle("control-center", "audio")
    function toggle(id, context) {
        const cmd = ["noctalia", "msg", "panel-toggle", id];
        if (context)
            cmd.push(context);
        Quickshell.execDetached(cmd);
    }
}
