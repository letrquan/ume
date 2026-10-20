import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.common
import qs.services

// One workspace in the overview: a small copy of the screen, with the
// wallpaper (a little darker) and its windows where they really are, its
// number in a glass chip. The one you're on has an accent ring.
//
// The "hero" is the workspace the overview zooms out of when it opens (the
// one you're on) and into when it closes (the one you picked): it goes
// between its place in the grid and the whole screen (t: 1 = in the grid,
// 0 = the whole screen). The others fade and grow in, one after another.
Item {
    id: root

    required property int tag
    property bool isNew: false
    property string monitor: ""
    property real screenWidth: 1536
    property real screenHeight: 960
    property real monitorX: 0
    property real monitorY: 0

    // Its place in the grid, and the whole screen (OverviewView's
    // coordinates).
    property rect cell: Qt.rect(0, 0, 100, 60)
    property rect full: Qt.rect(0, 0, screenWidth, screenHeight)
    property bool hero: false
    property real t: 1
    // In view: the overview is up (the cards come in staggered by `order`).
    property bool shown: false
    property int order: 0
    property bool animate: true

    property bool current: false
    property bool selected: false     // the keyboard's pick
    property bool dropHere: false     // a dragged window is over it
    property bool landed: false       // one just landed here (lights up)
    property int landedId: -1         // the window moved last (above the others)
    property bool pictures: true
    // Typing: which windows match ({ id: true }), or null when not searching.
    property var matches: null
    property int hiddenId: -1         // a window being dragged or landing
    property bool live: true          // new pictures show (not while it flies)
    property Item overlay: null

    signal picked()
    signal windowPicked(var client)
    signal windowCloseRequested(var client)
    signal windowDragStarted(var client, rect from, point at)
    signal windowDragMoved(point at)
    signal windowDragEnded(point at)

    // How small the screen is drawn.
    readonly property real k: width / Math.max(1, screenWidth)
    readonly property var windowIds: isNew ? [] : OverviewState.onTag(monitor, tag).map(c => c.id)

    // ---- Where it is ------------------------------------------------------------------
    readonly property real ht: hero ? t : 1
    x: full.x + (cell.x - full.x) * ht
    y: full.y + (cell.y - full.y) * ht
    width: full.width + (cell.width - full.width) * ht
    height: full.height + (cell.height - full.height) * ht
    z: hero ? 5 : (hovered ? 2 : 1)

    // The others: in one after another (all there when the zoom ends), out
    // together.
    readonly property int delay: Math.max(0, Math.min(150, 20 + order * 25))
    property real appear: 0
    Component.onCompleted: appear = shown ? 1 : 0
    onShownChanged: {
        if (!animate)
            return;
        comeIn.stop();
        if (shown) {
            comeIn.restart();
        } else {
            goOut.restart();
        }
    }
    SequentialAnimation {
        id: comeIn
        PauseAnimation { duration: root.delay }
        NumberAnimation { target: root; property: "appear"; to: 1; duration: Math.max(260, Style.overviewOpenMs - root.delay); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.overviewCurve }
    }
    NumberAnimation { id: goOut; target: root; property: "appear"; to: 0; duration: Style.overviewCloseMs * 0.6; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }

    opacity: hero ? 1 : appear
    readonly property bool hovered: hover.hovered && !hero
    HoverHandler {
        id: hover
    }
    scale: hero ? 1 : (0.9 + 0.1 * appear) * (hovered || dropHere || landed ? 1.025 : 1)
    Behavior on scale { enabled: root.appear > 0.99; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    readonly property real radius: Style.overviewCardRadius * ht

    // Every window picture that's there is loaded.
    readonly property bool picturesReady: {
        for (let i = 0; i < thumbs.count; i++) {
            const w = thumbs.itemAt(i);
            if (w && !w.pictureReady)
                return false;
        }
        return true;
    }

    // ---- Look --------------------------------------------------------------------------
    RectangularShadow {
        anchors.fill: card
        radius: root.radius
        blur: root.hovered || root.dropHere || root.landed ? 40 : 28
        offset: Qt.vector2d(0, 10)
        color: Style.alpha(Colors.shadow, 0.55 * root.ht)
        Behavior on blur { NumberAnimation { duration: 220 } }
    }

    // Rounded without an offscreen copy (ClippingRectangle made two, and the
    // zooming one got new ones every frame): a plain clip for the edges,
    // and everything inside rounds its own corners to the card's (the
    // wallpaper and windows by shaders, see WindowThumb).
    Item {
        id: card
        anchors.fill: parent
        clip: true
        // While fading in or out: as one picture, so the windows don't turn
        // see-through over the wallpaper.
        layer.enabled: !root.hero && root.appear > 0 && root.appear < 1
        layer.smooth: true

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: Colors.surface
        }

        // The screen at its real size, drawn k times smaller: its windows
        // simply sit where they really are.
        Item {
            id: screenCopy
            width: root.screenWidth
            height: root.screenHeight
            scale: root.k
            transformOrigin: Item.TopLeft
            // The card's corners, in here.
            readonly property real radius: root.radius / Math.max(0.01, root.k)

            Image {
                id: wall
                anchors.fill: parent
                visible: false
                source: Colors.wallpaper !== "" ? "file://" + Colors.wallpaper : ""
                // One decode, shared by every workspace (same size: the
                // pixmap cache hands out the same picture).
                sourceSize: Qt.size(root.screenWidth, root.screenHeight)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                mipmap: true
            }
            RoundedTexture {
                anchors.fill: parent
                visible: wall.status === Image.Ready
                source: wall
                radius: screenCopy.radius
            }
            // A little darker (not while it's the whole screen: then it looks
            // just like your desktop).
            Rectangle {
                anchors.fill: parent
                radius: screenCopy.radius
                color: "black"
                opacity: (root.isNew ? 0.4 : 0.14) * root.ht
            }

            Repeater {
                id: thumbs
                // Keyed by mango id: a title changing doesn't make a new one.
                model: ScriptModel {
                    values: root.windowIds
                }

                WindowThumb {
                    required property int modelData
                    clientId: modelData
                    k: root.k
                    cardRect: Qt.rect(0, 0, root.screenWidth, root.screenHeight)
                    cardRadius: screenCopy.radius
                    monitorX: root.monitorX
                    monitorY: root.monitorY
                    pictures: root.pictures
                    live: root.live
                    overlay: root.overlay
                    hidden: modelData === root.hiddenId
                    landed: modelData === root.landedId
                    dimmed: root.matches !== null && !root.matches[modelData]
                    matched: root.matches !== null && !!root.matches[modelData]

                    onPicked: if (client) root.windowPicked(client)
                    onCloseRequested: if (client) root.windowCloseRequested(client)
                    onDragStarted: (from, at) => root.windowDragStarted(client, from, at)
                    onDragMoved: at => root.windowDragMoved(at)
                    onDragEnded: at => root.windowDragEnded(at)
                }
            }
        }

        // "+": a new workspace. An empty one (all 9 shown): just quiet.
        Column {
            anchors.centerIn: parent
            spacing: 6
            visible: root.isNew || root.windowIds.length === 0
            opacity: root.ht

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.isNew
                name: "add"
                size: Math.max(24, root.height * 0.18)
                color: "white"
                opacity: 0.85
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.isNew ? "New workspace" : "Empty"
                role: "label"
                color: "white"
                opacity: root.isNew ? 0.85 : 0.55
            }
        }

        // Light on hover, accent tint while a window hovers over it (and
        // for a moment once it landed).
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: root.dropHere || root.landed ? Colors.primary : "white"
            opacity: root.dropHere ? 0.16 : root.landed ? 0.12 : (root.hovered ? 0.05 : 0)
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
    }

    // Rings: you're here (accent), picked with the keyboard or a window
    // about to land (accent, thicker), else a faint edge.
    Rectangle {
        anchors.fill: card
        anchors.margins: -4
        radius: root.radius + 4
        color: "transparent"
        opacity: root.ht
        border.width: root.dropHere || root.landed || root.selected ? 3 : (root.current ? 2.5 : 0)
        border.color: Colors.primary
        Behavior on border.width { NumberAnimation { duration: 160 } }
    }
    Rectangle {
        anchors.fill: card
        radius: root.radius
        color: "transparent"
        opacity: root.ht
        border.width: 1
        border.color: Style.alpha("white", root.hovered ? 0.3 : 0.14)
    }

    // The number, in a glass chip.
    Rectangle {
        x: 10
        y: 10
        width: Math.max(height, label.implicitWidth + 18)
        height: 26
        radius: 13
        opacity: root.ht
        color: root.current ? Colors.primary : Style.alpha(Colors.surfaceContainerHighest, 0.85)
        border.width: root.current ? 0 : 1
        border.color: Style.alpha("white", 0.14)

        StyledText {
            id: label
            anchors.centerIn: parent
            text: root.isNew ? "+" : String(root.tag)
            role: "body"
            weight: 700
            color: root.current ? Colors.textOnPrimary : Colors.textOnSurface
        }
    }

    // Under the windows: hover and click (go there).
    MouseArea {
        anchors.fill: parent
        z: -1
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
    }
}
