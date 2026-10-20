import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.common
import qs.services

// One tray icon. Left click: open the app, middle click: its second action,
// right click: its menu, scroll: whatever the app does with scrolling.
// fcitx5 (typing) is drawn as the language instead, EN or VI (ImeItem); for
// it a click switches English <-> Vietnamese like Super+Space (fcitx's own
// "activate"), right click is its menu, scroll goes through the input
// methods.
MouseArea {
    id: root

    required property SystemTrayItem modelData
    // fcitx5's item, and it says which language is on.
    readonly property bool isIme: modelData === OsdState.imeItem && OsdState.imeCode !== ""

    // Its tip on the bar (common/Tooltips.qml): the app's own tooltip, else
    // its name; for the typing language, which one and how to switch.
    readonly property string tip: isIme ? (OsdState.imeCode === "VI" ? "Tiếng Việt" : "English")
        : (modelData.tooltipTitle || modelData.title || modelData.id || "")
    readonly property string tipDetail: isIme ? "Click: switch · right-click: menu"
        : Tooltips.source === root ? root.plain(modelData.tooltipDescription ?? "") : ""
    readonly property string tipShortcut: ""
    // Apps send their tooltip text with markup: just the words.
    function plain(text) {
        return text.replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ")
                   .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&").trim();
    }
    onContainsMouseChanged: {
        if (containsMouse ? Tooltips.hasTip(root) : Tooltips.hovered === root)
            Tooltips.hover(root, containsMouse);
    }
    onPressed: if (Tooltips.hovered === root || Tooltips.source === root) Tooltips.press(root)

    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: isIme ? ime.implicitWidth : Style.iconSize
    implicitHeight: Style.iconSize
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton)
            modelData.secondaryActivate();
        else if (mouse.button === Qt.LeftButton && !modelData.onlyMenu)
            modelData.activate();
        else if (modelData.hasMenu)
            openMenu();
    }

    // Open the menu centered under the icon, just below the bar. It's only
    // created while open.
    function openMenu() {
        menu.active = true;
        const win = root.QsWindow.window;
        const r = win.itemRect(root);
        const popup = menu.item;
        popup.anchor.rect.x = r.x;
        popup.anchor.rect.y = 0;
        popup.anchor.rect.width = r.width;
        popup.anchor.rect.height = win.height + 4;
        popup.visible = true;
    }
    onWheel: wheel => modelData.scroll(wheel.angleDelta.y || wheel.angleDelta.x, wheel.angleDelta.y === 0)

    IconImage {
        anchors.fill: parent
        visible: !root.isIme
        source: root.isIme ? "" : root.modelData.icon
        asynchronous: true
        scale: root.pressed ? 0.85 : root.containsMouse ? 1.12 : 1

        Behavior on scale {
            NumberAnimation {
                duration: Motion.fast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fastSpatial
            }
        }
    }

    ImeItem {
        id: ime
        anchors.centerIn: parent
        visible: root.isIme
        code: OsdState.imeCode
        scale: root.pressed ? 0.85 : root.containsMouse ? 1.08 : 1

        Behavior on scale {
            NumberAnimation {
                duration: Motion.fast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fastSpatial
            }
        }
    }

    // The app's own menu, drawn in our glass, opened under the icon.
    LazyLoader {
        id: menu

        TrayMenu {
            handle: root.modelData.menu
            anchor.window: root.QsWindow.window
            anchor.edges: Edges.Bottom
            anchor.gravity: Edges.Bottom
            onDismissed: menu.active = false
        }
    }
}
