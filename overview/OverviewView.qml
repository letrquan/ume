import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import qs.common
import qs.services

// The overview: every workspace as a small copy of the screen, in a grid.
//
//    ╭──── 1 ────╮ ╭──── 2 ────╮ ╭──── 3 ────╮
//    │┌───┐┌───┐│ │┌────────┐│ │┌────┐┌──┐│      its windows where they
//    ││ >_││ >_││ ││  zen   ││ ││disc││♫ ││      really are, as pictures
//    │└───┘└───┘│ │└────────┘│ │└────┘└──┘│
//    ╰───────────╯ ╰───────────╯ ╰───────────╯
//                  ╭──── + ────╮                   a new one
//                  ╰───────────╯
//              ( ⌕ Type to find a window )
//
// Opening, the workspace you're on starts as the whole screen and shrinks
// into its place while the others come in; closing, the one you picked
// grows back into the whole screen. The screen behind dims (mango blurs it).
//
// Plain QtQuick + OverviewState, so it can be previewed offscreen.
Item {
    id: root

    property string monitor: ""
    property bool shown: false
    // False: nothing drawn yet (OverviewWindow waits for mango's lists and
    // the pictures, see there).
    property bool revealed: true
    property bool pictures: Style.overviewLive
    // Off: no opening/closing animation (previews set `t` by hand).
    property bool animate: true

    signal closeRequested()
    // Closing: the windows are back where they really are (t reached 0).
    signal flownBack()

    opacity: revealed ? 1 : 0

    function focusInput() {
        input.forceActiveFocus();
    }

    readonly property var mon: OverviewState.monitors[monitor] ?? null
    readonly property real monX: mon?.x ?? 0
    readonly property real monY: mon?.y ?? 0
    readonly property real screenW: mon?.width || width
    readonly property real screenH: mon?.height || height
    readonly property int current: OverviewState.activeTag(monitor)
    readonly property bool searching: OverviewState.query.trim() !== ""

    // ---- Which workspaces ---------------------------------------------------------
    // The ones with windows and yours, then "+" (the first empty one); or
    // all of them (Style.overviewShowAll).
    readonly property var cards: {
        if (Style.overviewShowAll) {
            const count = mon?.tagCount ?? 9;
            return Array.from({ length: count }, (_, i) => ({ tag: i + 1, isNew: false }));
        }
        const out = OverviewState.tagsOf(monitor).map(t => ({ tag: t, isNew: false }));
        const free = OverviewState.freeTag(monitor);
        if (free > 0)
            out.push({ tag: free, isNew: true });
        return out;
    }
    readonly property var cardKeys: cards.map(c => (c.isNew ? "n" : "t") + c.tag)
    function indexOfTag(tag) {
        return cards.findIndex(c => c.tag === tag);
    }

    // ---- The grid ----------------------------------------------------------------------
    readonly property real gap: Style.overviewGap
    readonly property real topSpace: 44
    readonly property real bottomSpace: 104       // the search field
    readonly property real sideSpace: 64
    readonly property real aspect: screenW / Math.max(1, screenH)
    // How wide a workspace can be with `cols` per row (never more than 62 %
    // of the screen wide).
    function widthFor(cols) {
        const rowsNeeded = Math.ceil(cards.length / cols);
        return Math.min((width - 2 * sideSpace - gap * (cols - 1)) / cols,
                        ((height - topSpace - bottomSpace - gap * (rowsNeeded - 1)) / rowsNeeded) * aspect,
                        width * 0.62);
    }
    // As many per row as gives the biggest workspaces (up to
    // Style.overviewColumns): 4 of them sit 2 by 2, 5 of them 3 + 2.
    readonly property int columns: {
        const most = Math.max(1, Math.min(Style.overviewColumns, cards.length));
        let best = most;
        for (let c = most; c >= 1; c--)
            if (widthFor(c) > widthFor(best) + 1)
                best = c;
        return best;
    }
    readonly property int rows: Math.ceil(cards.length / columns)
    readonly property real cellW: Math.max(40, widthFor(columns))
    readonly property real cellH: cellW / aspect
    readonly property real gridTop: topSpace + (height - topSpace - bottomSpace - (rows * cellH + (rows - 1) * gap)) / 2

    function cellRect(i) {
        const row = Math.floor(i / columns);
        const col = i % columns;
        const inRow = Math.min(columns, cards.length - row * columns);
        const rowW = inRow * cellW + (inRow - 1) * gap;
        return Qt.rect((width - rowW) / 2 + col * (cellW + gap), gridTop + row * (cellH + gap), cellW, cellH);
    }
    // The workspace under a point (0 = none).
    function tagAt(x, y) {
        for (let i = 0; i < cards.length; i++) {
            const r = cellRect(i);
            if (x >= r.x - 6 && y >= r.y - 6 && x <= r.x + r.width + 6 && y <= r.y + r.height + 6)
                return cards[i].tag;
        }
        return 0;
    }

    // ---- Opening and closing -------------------------------------------------------
    // 0 = the hero is the whole screen, 1 = everything in the grid.
    property real t: 0
    Component.onCompleted: t = Qt.binding(() => root.shown ? 1 : 0)
    Behavior on t {
        enabled: root.animate
        NumberAnimation {
            duration: root.shown ? Style.overviewOpenMs : Style.overviewCloseMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Style.overviewCurve
        }
    }
    onTChanged: if (!shown && t <= 0 && revealed) flownBack()
    // All the way out: only now are pictures taken (taking them makes mango
    // skip frames; the zoom shows the last ones).
    readonly property bool settled: shown && t >= 1
    // Out of the one you're on; into the one you picked.
    readonly property int heroTag: shown ? current : (OverviewState.closeTag > 0 ? OverviewState.closeTag : current)

    // ---- Typing ----------------------------------------------------------------------
    readonly property var matchList: searching ? OverviewState.matching(OverviewState.query)
        .filter(c => c.monitor === monitor)
        .sort((a, b) => ((a.tag === current ? 0 : 1) - (b.tag === current ? 0 : 1)) || (a.tag - b.tag) || (a.y - b.y) || (a.x - b.x)) : []
    readonly property var matches: {
        if (!searching)
            return null;
        const out = {};
        for (const c of matchList)
            out[c.id] = true;
        return out;
    }

    // Keyboard: a workspace (-1 = none yet).
    property int selected: -1
    onCardKeysChanged: if (selected >= cards.length) selected = cards.length - 1
    function move(dx, dy) {
        const n = cards.length;
        if (n === 0)
            return;
        if (selected < 0)
            selected = Math.max(0, indexOfTag(current));
        let i = selected + dx + dy * columns;
        if (dy !== 0 && (i < 0 || i >= n))
            return;
        selected = (i + n) % n;
    }
    function enter() {
        if (searching) {
            if (matchList.length > 0)
                OverviewState.focus(matchList[0]);
            return;
        }
        const c = cards[selected >= 0 ? selected : indexOfTag(current)];
        if (c)
            OverviewState.view(c.tag);
    }

    // ---- Dragging a window to another workspace ----------------------------------
    // While dragged, a copy of the window follows the pointer above
    // everything (the window itself hides). Let go over a workspace: it
    // moves there (here right away; mango's next list confirms) and the copy
    // flies into the place mango will tile it at there (OverviewState.shape());
    // that workspace lights up, the window stays above the others there,
    // and the search field says so once mango has moved it. Anywhere else:
    // it flies back.
    property int dropTag: 0
    property int landedTag: 0      // lit up: a window just landed there
    property int landedId: -1      // the last window moved: above the others
    property string note: ""       // "Moved to workspace 4", for a moment
    property var dragClient: null
    property int hiddenId: -1
    property point grab: Qt.point(0, 0)      // where in the copy you hold it

    function dragStart(c, from, at) {
        if (!c)
            return;
        flight.stop();
        dragClient = c;
        hiddenId = c.id;
        grab = Qt.point(at.x - from.x, at.y - from.y);
        ghost.x = from.x;
        ghost.y = from.y;
        ghost.width = from.width;
        ghost.height = from.height;
        ghost.from = from;
        ghost.lift = 1;
        ghost.visible = true;
        dropTag = 0;
        landedTag = 0;
    }
    function dragMove(at) {
        if (!dragClient)
            return;
        ghost.x = at.x - grab.x;
        ghost.y = at.y - grab.y;
        const tag = tagAt(at.x, at.y);
        dropTag = tag !== dragClient.tag ? tag : 0;
    }
    function dragEnd(at) {
        const c = dragClient;
        if (!c)
            return;
        const tag = at.x >= 0 ? tagAt(at.x, at.y) : 0;
        dropTag = 0;
        ghost.lift = 0;
        if (tag > 0 && tag !== c.tag && OverviewState.moveTo(c, tag)) {
            landedTag = tag;
            landedId = c.id;
            landedFlash.restart();
            // Its place in the other workspace (where mango will tile it; if
            // it puts it elsewhere, it glides there).
            const n = OverviewState.byId[c.id] ?? c;
            const i = indexOfTag(tag);
            const r = cellRect(Math.max(0, i));
            const k = r.width / Math.max(1, screenW);
            flyTo(Qt.rect(r.x + (n.x - monX) * k, r.y + (n.y - monY) * k, n.width * k, n.height * k));
        } else {
            if (at.x >= 0)
                console.log("overview: dropped", c.appId, "(" + c.id + ") on no other workspace, at", Math.round(at.x) + "," + Math.round(at.y));
            flyTo(Qt.rect(ghost.from.x, ghost.from.y, ghost.from.width, ghost.from.height));
        }
        dragClient = null;
    }
    Timer {
        id: landedFlash
        interval: 700
        onTriggered: root.landedTag = 0
    }
    Timer {
        id: noteGone
        interval: 2200
        onTriggered: root.note = ""
    }
    function flyTo(r) {
        flight.stop();
        flyX.to = r.x;
        flyY.to = r.y;
        flyW.to = r.width;
        flyH.to = r.height;
        flight.start();
    }
    ParallelAnimation {
        id: flight
        NumberAnimation { id: flyX; target: ghost; property: "x"; duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.overviewCurve }
        NumberAnimation { id: flyY; target: ghost; property: "y"; duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.overviewCurve }
        NumberAnimation { id: flyW; target: ghost; property: "width"; duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.overviewCurve }
        NumberAnimation { id: flyH; target: ghost; property: "height"; duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.overviewCurve }
        onFinished: {
            ghost.visible = false;
            root.hiddenId = -1;
        }
    }

    // ---- Pictures ---------------------------------------------------------------------
    // About as sharp as they're drawn: the one you're on at every pixel of
    // the screen (it's the whole screen when the overview opens and closes),
    // the others at their size in the grid. The last ones show at once
    // (WindowShots keeps them); new ones crossfade in. Taken only while
    // nothing flies (`settled`).
    // The window's own pixel ratio (1.25 here; Screen's is the whole-number
    // output scale, 2, which took the small pictures 2.56× too big).
    readonly property real outputScale: QsWindow.window?.devicePixelRatio || Screen.devicePixelRatio || 1
    function scaleFor(c) {
        if (c.tag === current || c.tag === OverviewState.closeTag || c.tag === warmTag)
            return outputScale;
        return Math.min(outputScale, (cellW / Math.max(1, screenW)) * outputScale * 1.15);
    }
    function shoot(list) {
        if (pictures && settled && list.length > 0)
            WindowShots.capture(list.map(c => ({ id: c.ftid, scale: scaleFor(c), kind: "ov" })));
    }
    property var shot: ({})       // windows taken once already (this opening)
    onSettledChanged: if (settled) shootNew()
    // Flying back: pictures still to be taken aren't, and the ones on the
    // way don't change the windows mid-zoom (WindowThumb `live`).
    onShownChanged: if (!shown) WindowShots.cancel("ov")
    function shootNew() {
        if (!settled)
            return;
        const fresh = OverviewState.onMonitor(monitor).filter(c => !shot[c.id]);
        if (fresh.length === 0)
            return;
        shoot(fresh);
        const s = Object.assign({}, shot);
        for (const c of fresh)
            s[c.id] = true;
        shot = s;
    }
    Connections {
        target: OverviewState
        function onClientsChanged() { newWindows.restart(); }
        function onMoved(id, tag) {
            if (OverviewState.byId[id]?.monitor !== root.monitor)
                return;
            root.note = "Moved to workspace " + tag;
            noteGone.restart();
        }
    }
    // The workspace you rest the pointer on (or pick with the keys) is
    // likely the one you zoom into: sharp pictures of it now, while nothing
    // flies (not once the zoom has started: that would make it stutter).
    property int warmTag: 0       // the one taken sharp (one at a time)
    property int restTag: 0
    onSelectedChanged: if (selected >= 0 && cards[selected] && !cards[selected].isNew) restTag = cards[selected].tag
    onRestTagChanged: warmUp.restart()
    Timer {
        id: warmUp
        interval: 150
        onTriggered: {
            const tag = root.restTag;
            if (tag <= 0 || tag === root.current || tag === root.warmTag || !root.settled)
                return;
            root.warmTag = tag;
            root.shoot(OverviewState.onTag(root.monitor, tag));
        }
    }
    Timer {
        id: newWindows
        interval: 40
        onTriggered: root.shootNew()
    }
    // Yours often, the others now and then. A window whose picture came
    // back the same (it didn't change) is taken every 2nd, then every 4th
    // time; once it changes, every time again.
    property var calm: ({})        // ftid → pictures in a row that were the same
    function due(list, round) {
        return list.filter(c => round % (1 << Math.min(2, calm[c.ftid] ?? 0)) === 0);
    }
    Connections {
        target: WindowShots
        function onTaken(key, changed) {
            const m = key.match(/^([0-9a-f]+)-ov$/i);
            if (m)
                root.calm[m[1]] = changed ? 0 : Math.min(2, (root.calm[m[1]] ?? 0) + 1);
        }
    }
    Timer {
        interval: Math.max(250, Style.overviewRefresh)
        running: root.settled && root.pictures && Style.overviewRefresh > 0
        repeat: true
        property int round: 0
        onTriggered: root.shoot(root.due(OverviewState.onTag(root.monitor, root.current), ++round))
    }
    Timer {
        interval: Math.max(3000, Style.overviewRefresh * 4)
        running: root.settled && root.pictures && Style.overviewRefresh > 0
        repeat: true
        property int round: 0
        // (Not the sharp one you rest on: it would come back small.)
        onTriggered: root.shoot(root.due(OverviewState.onMonitor(root.monitor).filter(c => c.tag !== root.current && c.tag !== root.warmTag), ++round))
    }

    // ---- Look -----------------------------------------------------------------------
    // The screen behind dims (and mango blurs it).
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: Style.overviewDim * root.t
    }
    // A click on nothing closes it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.closeRequested()
    }

    // The pictures of the workspace you're on are loaded (OverviewWindow
    // waits for them: it starts as the whole screen). The others' may come
    // a moment later, while they fade in.
    readonly property bool picturesReady: {
        for (let i = 0; i < workspaces.count; i++) {
            const w = workspaces.itemAt(i);
            if (w && w.hero && !w.picturesReady)
                return false;
        }
        return true;
    }

    Repeater {
        id: workspaces
        model: ScriptModel {
            values: root.cardKeys
        }

        WorkspaceScreen {
            required property string modelData
            required property int index
            tag: Number(modelData.substring(1))
            isNew: modelData.startsWith("n")
            monitor: root.monitor
            screenWidth: root.screenW
            screenHeight: root.screenH
            monitorX: root.monX
            monitorY: root.monY
            cell: root.cellRect(index)
            full: Qt.rect(0, 0, root.width, root.height)
            // ("+" only when you picked it: it's never the one you're on.)
            hero: tag === root.heroTag && (!isNew || !root.shown)
            t: root.t
            shown: root.shown
            order: index
            animate: root.animate
            current: !isNew && tag === root.current
            selected: index === root.selected && !root.searching
            dropHere: root.dropTag !== 0 && root.dropTag === tag
            landed: !isNew && root.landedTag === tag
            landedId: root.landedId
            pictures: root.pictures
            matches: root.matches
            hiddenId: root.hiddenId
            live: root.settled
            overlay: root

            onHoveredChanged: if (hovered) root.restTag = tag
            onPicked: OverviewState.view(tag)
            onWindowPicked: c => OverviewState.focus(c)
            onWindowCloseRequested: c => OverviewState.closeWindow(c)
            onWindowDragStarted: (c, from, at) => root.dragStart(c, from, at)
            onWindowDragMoved: at => root.dragMove(at)
            onWindowDragEnded: at => root.dragEnd(at)
        }
    }

    // The dragged window's copy: lifted (a little bigger, a deeper shadow).
    Item {
        id: ghost
        visible: false
        z: 50
        property real lift: 0
        property rect from: Qt.rect(0, 0, 0, 0)       // where it was picked up
        Behavior on lift { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        transform: Scale {
            origin.x: root.grab.x
            origin.y: root.grab.y
            xScale: 1 + 0.05 * ghost.lift
            yScale: 1 + 0.05 * ghost.lift
        }

        RectangularShadow {
            anchors.fill: parent
            radius: 8
            blur: 24 + 26 * ghost.lift
            offset: Qt.vector2d(0, 6 + 12 * ghost.lift)
            color: Style.alpha(Colors.shadow, 0.5 + 0.2 * ghost.lift)
        }
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Style.alpha(Colors.surfaceContainer, 0.95)

            AppIcon {
                readonly property var c: ghost.visible ? OverviewState.byId[root.hiddenId] : null
                readonly property var entry: c ? (DesktopEntries.byId(c.appId) ?? DesktopEntries.heuristicLookup(c.appId)) : null
                anchors.centerIn: parent
                implicitSize: Math.min(64, parent.width * 0.4, parent.height * 0.5)
                visible: c !== null
                source: {
                    const icon = entry?.icon ?? c?.appId ?? "";
                    return icon.startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon, "application-x-executable");
                }
                name: entry?.name ?? c?.appId ?? ""
                opacity: ghostPicture.ready ? 0 : 1
            }
            CrossImage {
                id: ghostPicture
                anchors.fill: parent
                radius: 8
                source: root.pictures ? WindowShots.url(OverviewState.byId[root.hiddenId]?.ftid ?? "", "ov") : ""
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: 11
            color: "transparent"
            border.width: 2.5
            border.color: Colors.primary
            opacity: ghost.lift
        }
    }

    // ---- The search field ------------------------------------------------------------
    Item {
        id: search
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - 76 + (1 - root.t) * 24
        width: 440
        height: 46
        opacity: root.t

        RectangularShadow {
            anchors.fill: parent
            radius: 23
            blur: 24
            offset: Qt.vector2d(0, 6)
            color: Style.alpha(Colors.shadow, 0.35)
        }
        Glass {
            anchors.fill: parent
            radius: 23
            color: Style.alpha(Colors.surfaceContainer, 0.82)
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 20
                color: root.searching ? Colors.primary : Colors.textOnSurfaceVariant
            }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 30 - hint.width - 20
                height: 24

                TextInput {
                    id: input
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Style.font
                    font.variableAxes: ({ "wght": 500, "ROND": 100 })
                    font.pixelSize: Style.textSize("title")
                    color: Colors.textOnSurface
                    selectionColor: Style.alpha(Colors.primary, 0.4)
                    clip: true
                    text: OverviewState.query
                    onTextChanged: OverviewState.query = text

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Escape:
                            if (text !== "")
                                text = "";
                            else
                                root.closeRequested();
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.enter();
                            break;
                        case Qt.Key_Right:
                            root.move(1, 0);
                            break;
                        case Qt.Key_Left:
                            root.move(-1, 0);
                            break;
                        case Qt.Key_Down:
                            root.move(0, 1);
                            break;
                        case Qt.Key_Up:
                            root.move(0, -1);
                            break;
                        case Qt.Key_Tab:
                            root.move(1, 0);
                            break;
                        case Qt.Key_Backtab:
                            root.move(-1, 0);
                            break;
                        default:
                            return;
                        }
                        event.accepted = true;
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: "Type to find a window"
                    font.pixelSize: Style.textSize("title")
                    color: Colors.textOnSurfaceVariant
                }
            }
            StyledText {
                id: hint
                anchors.verticalCenter: parent.verticalCenter
                text: root.note !== "" ? root.note
                    : root.searching ? (root.matchList.length === 1 ? "1 window" : root.matchList.length + " windows") : "drag to move"
                role: "caption"
                weight: root.note !== "" ? 600 : Style.fontWeight
                color: root.note !== "" ? Colors.primary : Colors.textOnSurfaceVariant
                opacity: root.note !== "" ? 1 : 0.8
            }
        }
    }
}
