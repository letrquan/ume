import QtQuick
import Quickshell
import qs.common
import qs.services

// One window inside a workspace of the overview. It lives in the
// workspace's full-size copy of the screen (WorkspaceScreen scales that
// down), so it simply sits where the window really is, at its real size,
// with its picture (services/WindowShots.qml; its app's icon until the
// first one is in). Things that must stay readable however small the
// workspace is drawn (the title chip, ✕, the ring) are scaled back up by 1/k.
//
// Click: go to it. Middle-click: close it. Drag: OverviewView takes it from
// here (a copy follows the pointer above everything).
Item {
    id: root

    required property int clientId
    readonly property var client: OverviewState.byId[clientId] ?? null

    // How small the workspace is drawn (1 = full size).
    property real k: 1
    // The workspace's rounded box, in its screen copy's coordinates: the
    // window (and its shadow) is cut to its corners.
    property rect cardRect: Qt.rect(-1e6, -1e6, 2e6, 2e6)
    property real cardRadius: 0
    property real monitorX: 0
    property real monitorY: 0
    property bool pictures: true
    // Typing: not a match (dimmed) / a match (ring).
    property bool dimmed: false
    property bool matched: false
    // Being dragged, or landing elsewhere: OverviewView's copy shows instead.
    property bool hidden: false
    // The window moved last: above the others (mango may not have tiled
    // it there yet).
    property bool landed: false
    // The item the drag is measured in (OverviewView): its coordinates don't
    // move while the copy follows the pointer.
    property Item overlay: null

    signal picked()
    signal closeRequested()
    signal dragStarted(rect from, point at)
    signal dragMoved(point at)
    signal dragEnded(point at)

    x: (client?.x ?? 0) - monitorX
    y: (client?.y ?? 0) - monitorY
    width: client?.width ?? 1
    height: client?.height ?? 1
    // mango tiles again after a move: glide to the new place.
    Behavior on x { enabled: root.settled; NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.overviewCurve } }
    Behavior on y { enabled: root.settled; NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.overviewCurve } }
    Behavior on width { enabled: root.settled; NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.overviewCurve } }
    Behavior on height { enabled: root.settled; NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.overviewCurve } }
    // The picture shown: the newest one, but while the overview flies only
    // the first (a new one would load and fade in mid-zoom).
    property bool live: true
    readonly property url latestUrl: pictures ? WindowShots.url(client?.ftid ?? "", "ov") : ""
    property url pictureUrl: ""
    onLatestUrlChanged: if (live || pictureUrl == "" || latestUrl == "") pictureUrl = latestUrl
    onLiveChanged: if (live) pictureUrl = latestUrl
    // Its picture is loaded (or there's none to wait for).
    readonly property bool pictureReady: picture.ready || pictureUrl == ""
    // The icon: no picture, or it's slow to come.
    property bool slowPicture: false
    readonly property bool showIcon: pictureUrl == "" || slowPicture
    Timer {
        interval: 300
        running: !picture.ready && !root.slowPicture
        onTriggered: root.slowPicture = true
    }
    // No gliding into the first place.
    property bool settled: false
    Component.onCompleted: {
        pictureUrl = latestUrl;
        Qt.callLater(() => root.settled = true);
    }

    opacity: hidden ? 0 : (dimmed ? 0.3 : 1)
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects } }

    readonly property bool hovered: pointer.containsMouse || closeArea.containsMouse
    // Hover: a little lift.
    scale: hovered && !hidden ? 1.02 : 1
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    z: hovered ? 3 : (landed ? 2 : 1)

    // mango's corners, at this screen's size.
    readonly property real radius: 12
    // The workspace's box in this window's own coordinates (it may be lifted
    // a little: scaled around its middle).
    readonly property rect cardClip: {
        const s = scale, cx = width / 2, cy = height / 2;
        return Qt.rect(cx + (cardRect.x - x - cx) / s, cy + (cardRect.y - y - cy) / s,
                       cardRect.width / s, cardRect.height / s);
    }
    readonly property real cardClipRadius: cardRadius / scale

    function nameFor(appId) {
        const entry = DesktopEntries.applications.values.length >= 0 && appId
            ? (DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId)) : null;
        return entry?.name ?? appId ?? "";
    }
    function iconFor(appId) {
        const entry = DesktopEntries.applications.values.length >= 0 && appId
            ? (DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId)) : null;
        const icon = entry?.icon ?? appId ?? "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }

    // Rounded and cut to the workspace's corners by shaders (RoundedBox,
    // CrossImage's RoundedTexture), not ClippingRectangle: that drew every
    // window into two offscreen copies at its full size.
    Item {
        id: frame
        anchors.fill: parent

        RoundedBox {
            anchors.fill: parent
            anchors.margins: -pad
            radius: root.radius
            color: Style.alpha(Colors.surfaceContainer, 0.92)
            shadowColor: Style.alpha(Colors.shadow, root.hovered ? 0.6 : 0.42)
            shadowBlur: 48
            shadowOffset: Qt.point(0, 14)
            clipRect: root.cardClip
            clipRadius: root.cardClipRadius
            Behavior on shadowColor { ColorAnimation { duration: 200 } }
        }

        // Until (or unless) there's a picture: the app's icon, big. Only
        // looked up when needed: the pictures wait in the same queue.
        AppIcon {
            anchors.centerIn: parent
            width: Math.min(160, parent.width * 0.3, parent.height * 0.4)
            height: width
            visible: root.showIcon
            source: root.showIcon ? root.iconFor(root.client?.appId) : ""
            name: root.showIcon ? root.nameFor(root.client?.appId) : ""
            sourceSize: Qt.size(256, 256)
            opacity: picture.ready ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }

        CrossImage {
            id: picture
            anchors.fill: parent
            source: root.pictureUrl
            radius: root.radius
            clipRect: root.cardClip
            clipRadius: root.cardClipRadius
        }
    }

    // A ring: hovered, or a match while typing. 2 px however small.
    RoundedBox {
        anchors.fill: frame
        anchors.margins: -3 / root.k
        radius: root.radius + 3 / root.k
        borderWidth: 2.5 / root.k
        borderColor: Colors.primary
        clipRect: Qt.rect(root.cardClip.x + 3 / root.k, root.cardClip.y + 3 / root.k, root.cardClip.width, root.cardClip.height)
        clipRadius: root.cardClipRadius
        opacity: (root.hovered || root.matched) && !root.hidden ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        preventStealing: true

        // Measured in the overlay's coordinates: they don't move while the
        // copy follows the pointer.
        property point pressAt: Qt.point(0, 0)
        property bool dragging: false
        // A drag ends in a release: not a click.
        property bool wasDrag: false

        function onOverlay(mouse) {
            return root.overlay ? mapToItem(root.overlay, mouse.x, mouse.y) : Qt.point(mouse.x, mouse.y);
        }

        onPressed: mouse => {
            pressAt = onOverlay(mouse);
            wasDrag = false;
        }
        onPositionChanged: mouse => {
            if (!pressed || !(mouse.buttons & Qt.LeftButton) || !root.overlay)
                return;
            const p = onOverlay(mouse);
            if (!dragging && Math.hypot(p.x - pressAt.x, p.y - pressAt.y) > 6) {
                dragging = true;
                wasDrag = true;
                const r = frame.mapToItem(root.overlay, 0, 0, frame.width, frame.height);
                root.dragStarted(r, pressAt);
            }
            if (dragging)
                root.dragMoved(p);
        }
        onReleased: mouse => {
            if (!dragging)
                return;
            dragging = false;
            root.dragEnded(onOverlay(mouse));
        }
        onCanceled: {
            if (dragging) {
                dragging = false;
                root.dragEnded(Qt.point(-1, -1));
            }
        }
        onClicked: mouse => {
            if (wasDrag)
                return;
            if (mouse.button === Qt.MiddleButton)
                root.closeRequested();
            else
                root.picked();
        }
    }

    // ---- Hover: the title, and ✕ ---------------------------------------------------
    // Scaled back up (1/k), so they're the same size however small the
    // workspace is.
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10 / root.k
        width: chip.width
        height: chip.height
        scale: 1 / root.k
        transformOrigin: Item.Bottom
        opacity: root.hovered && !root.hidden ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Rectangle {
            id: chip
            width: Math.min(chipRow.implicitWidth + 20, 280)
            height: 28
            radius: 14
            color: Style.alpha(Colors.surfaceContainerHighest, 0.92)
            border.width: 1
            border.color: Style.alpha("white", 0.12)

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6
                width: Math.min(implicitWidth, 260)

                AppIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 16
                    source: root.hovered ? root.iconFor(root.client?.appId) : ""
                    name: root.hovered ? root.nameFor(root.client?.appId) : ""
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 236)
                    text: root.client?.title || root.client?.appId || ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    role: "label"
                }
            }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8 / root.k
        width: 24
        height: 24
        radius: 12
        scale: (root.hovered && !root.hidden ? 1 : 0.6) / root.k
        transformOrigin: Item.TopRight
        color: closeArea.containsMouse ? Colors.error : Style.alpha(Colors.surfaceContainerHighest, 0.92)
        border.width: 1
        border.color: Style.alpha("white", 0.14)
        opacity: root.hovered && !root.hidden ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        Icon {
            anchors.centerIn: parent
            name: "close"
            size: 15
            color: closeArea.containsMouse ? Colors.textOnError : Colors.textOnSurface
        }

        MouseArea {
            id: closeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closeRequested()
        }
    }
}
