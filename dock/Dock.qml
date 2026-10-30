import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.corners
import qs.overview
import qs.services

// The dock window on one screen: a see-through strip along the bottom
// (tall enough for grown icons and the name label, or the window preview
// card over them). Windows stay above
// the dock bar (Style.dockReserve, "always" only); only the dock itself
// takes clicks. With Style.dockBehavior "autohide" / "smart" it slides
// away (DockReveal.qml) and a thin strip at the bottom edge under it
// brings it back.
PanelWindow {
    id: root

    required property ShellScreen modelData

    screen: modelData
    // Out of the way while the on-screen keyboard is up (mango would stack
    // it above the keyboard, its bottom screen corners with it).
    visible: !OskState.open
    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: Style.dockMarginEdge + view.barHeight + view.rowHeight + 48
        + (Style.dockPreviews ? Style.dockPreviewSize + 70 : 0)
    exclusiveZone: !reveal.hides && Style.dockReserve ? Style.dockMarginEdge + view.barHeight : 0
    color: "transparent"

    // Badges (services/Badges.qml) listen to apps only while a dock is there.
    Component.onCompleted: Badges.docks++
    Component.onDestruction: Badges.docks--

    WlrLayershell.namespace: "mine-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // The bar while it's out (or sliding), the preview card while it's
    // there, plus the edge strip when it hides.
    mask: Region {
        item: reveal.slide < 0.999 ? view.hitArea : null

        Region {
            item: view.previewCard.visible ? view.previewCard : null
        }
        Region {
            item: reveal.hides ? edge : null
        }
        Region {
            item: hotCorner.active ? hotCorner : null
        }
    }

    DockReveal {
        id: reveal
        pointerHere: view.hovered || edgeHover.hovered
        busy: menu.visible
        windowsHere: {
            const m = root.mangoMonitor;
            return m ? (m.tags.find(t => t.index === m.activeTag)?.clients ?? 0) : 0;
        }
    }

    // How many windows the workspace has ("smart" only): the bar's
    // MangoMonitor of this screen, so there's no second `mmsg watch`.
    readonly property var mangoMonitor: reveal.behavior === "smart" ? (Monitors.byScreen[modelData.name] ?? null) : null

    // Touching the bottom edge under the dock brings it back; while it's
    // out, the strip also covers the gap under the bar, so the pointer
    // resting on the edge keeps it out.
    Item {
        id: edge
        width: view.hitArea.width + 40
        height: reveal.shown ? Math.max(Style.dockRevealZone, Style.dockMarginEdge) : Style.dockRevealZone
        x: Math.round((root.width - width) / 2)
        y: root.height - height

        HoverHandler {
            id: edgeHover
        }
    }

    DockView {
        id: view
        anchors.fill: parent
        slide: reveal.slide
        menuOpen: menu.visible
        onMenuRequested: slot => {
            menuView.item = slot.item;
            const r = root.itemRect(slot);
            menu.anchor.rect.x = r.x;
            // Just above the icon's top.
            menu.anchor.rect.y = r.y + r.height - slot.size - 10;
            menu.anchor.rect.width = r.width;
            menu.anchor.rect.height = 1;
            menu.visible = true;
        }
    }

    // The screen's two bottom rounded corners live here (no windows of their
    // own); outside the mask, so they never take a click.
    CornerShape {
        x: root.width - width
        y: root.height - height
        visible: Style.cornersEnabled
        turn: 180
    }
    CornerShape {
        y: root.height - height
        visible: Style.cornersEnabled
        turn: 270
    }

    // The overview's hot corner, when it's a bottom one (the dock's window
    // spans the screen's bottom edge, sliding or not).
    HotCorner {
        id: hotCorner
        edge: "bottom"
    }

    // Right-click menu: closes on a click anywhere else.
    PopupWindow {
        id: menu

        anchor.window: root
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        grabFocus: true
        implicitWidth: menuView.implicitWidth
        implicitHeight: menuView.implicitHeight
        color: "transparent"

        DockMenuView {
            id: menuView
            anchors.fill: parent
            onDone: menu.visible = false
        }
    }
}
