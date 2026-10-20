pragma Singleton
import QtQuick
import Quickshell

// The bar's tooltips: which item the mouse is on, and whether its tip is
// out. An item says what its tip is (Clickable's `tip`, `tipDetail` and
// `tipShortcut`, or a TipArea for one that isn't clickable) and calls
// hover() and press(); the bar draws the tip under it
// (bar/TooltipWindow.qml).
//
// The first tip waits Style.tooltipDelay. Sliding along the bar after that,
// the tip follows from item to item at once, and coming back soon after it
// went (Style.tooltipDelay again) needs no wait either. A click hides it
// until the mouse leaves that item. The window is made at the first hover
// (so it's ready by the time the tip shows) and goes a while after the
// last tip.
Singleton {
    id: root

    // The item the mouse is on (one with a tip), or null.
    property var hovered: null
    // The item whose tip is out; it stays set while the tip shrinks away.
    property var source: null
    property bool shown: false
    // The tip's window exists.
    property bool mapped: false
    // Where the tip goes: the screen, the middle of the item on it, and the
    // item's width (the tip grows out of it).
    property string screenName: ""
    property real anchorX: 0
    property real anchorWidth: 0
    // Clicked: no tip on this one again until the mouse leaves it.
    property var pressedOn: null
    // A tip was out a moment ago: the next one shows at once.
    property bool warm: false

    function hasTip(item) {
        return item !== null && item !== undefined
            && ((item.tip ?? "") !== "" || (item.tipDetail ?? "") !== "");
    }

    function hover(item, on) {
        if (!on) {
            if (pressedOn === item)
                pressedOn = null;
            if (hovered === item) {
                hovered = null;
                leave.restart();
            }
            return;
        }
        if (!Style.tooltipsEnabled || !hasTip(item) || pressedOn === item)
            return;
        hovered = item;
        leave.stop();
        unmap.stop();
        if (shown || warm)
            show(item);
        else {
            wait.restart();
            prepare.restart();
        }
    }

    // A click (or the item doing its thing): away until the mouse leaves.
    function press(item) {
        if (hovered === item || source === item) {
            pressedOn = item;
            hovered = null;
            hide();
            warm = false;
            cool.stop();
        }
    }

    // Something else takes the spot (a panel, the volume OSD).
    function hide() {
        wait.stop();
        prepare.stop();
        leave.stop();
        if (shown) {
            shown = false;
            cool.restart();
        }
        if (mapped)
            unmap.restart();
    }

    function show(item) {
        if (!place(item))
            return;
        mapped = true;
        source = item;
        shown = true;
        warm = true;
        cool.stop();
    }

    // Where the item is on its screen (the bar's window spans the screen,
    // so its x there is the screen's).
    function place(item) {
        const target = item?.tipItem ?? item;
        const win = target?.QsWindow?.window;
        if (!win || !target.visible)
            return false;
        const r = win.itemRect(target);
        screenName = win.screen?.name ?? "";
        anchorX = r.x + r.width / 2;
        anchorWidth = r.width;
        return true;
    }

    Timer {
        id: wait
        interval: Style.tooltipDelay
        onTriggered: if (root.hovered) root.show(root.hovered)
    }
    // The window, made once the mouse stays a moment (not for every pass
    // over the bar), so it has drawn its first frames before the tip shows.
    Timer {
        id: prepare
        interval: Math.min(150, Style.tooltipDelay / 2)
        onTriggered: if (root.hovered && root.place(root.hovered)) root.mapped = true
    }
    // Leaving one item for the next: a moment to arrive before hiding.
    Timer {
        id: leave
        interval: 90
        onTriggered: if (!root.hovered) root.hide()
    }
    Timer {
        id: cool
        interval: Style.tooltipDelay
        onTriggered: root.warm = false
    }
    Timer {
        id: unmap
        interval: 2500
        onTriggered: {
            if (!root.shown && !root.hovered) {
                root.mapped = false;
                root.source = null;
            }
        }
    }
    // Items move while the tip is out (an island growing, a hover text
    // sliding out next to it): follow them. One that went away (the phone
    // left, the title fits again) takes its tip with it.
    Timer {
        interval: 60
        repeat: true
        running: root.shown
        onTriggered: {
            if (!root.hasTip(root.source) || !root.place(root.source))
                root.hide();
        }
    }
}
