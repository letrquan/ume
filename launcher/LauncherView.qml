import QtQuick
import qs.common
import qs.services
import qs.settings

// The launcher. Like the notification island it starts exactly where the
// middle island is and stretches out of it, here into a search bar with
// the results dropping below, all one piece of glass.
//
//      ╭──────────────────────────────────────────────────╮
//      │ (⌕)  firef▌                                  esc │
//      ├──────────────────────────────────────────────────┤
//      │ ▌(🦊) Firefox          Web Browser               │ ← selected
//      │  (◍)  Search the web for “firef”                 │
//      ╰──────────────────────────────────────────────────╯
//
// Type to search (apps, settings, 2+3*4, a web address, or the web), ↑↓ /
// Tab to move, Enter to open, Esc to close. → at the end of the text (or
// the Menu key, a right click, a long press) opens the selected app's
// menu: its own actions ("New Private Window"…) and Pin to dock
// (AppMenu.qml). A sign first picks a mode, shown in a chip by the search
// field: ":" emoji (a grid; ←→↑↓ move, Enter copies), "/" or "~" files
// (Ctrl+Enter opens the folder), "?" the web, "tr " a translation (Enter
// copies it). With nothing typed, a row of chips lists them.
//
// The ▦ button (or `mine launcher grid`, or opening in tablet mode with
// Style.launcherGridInTablet) turns the card into a Launchpad: the same
// glass grows into a big sheet of app tiles with group chips on top
// (AppGrid.qml), finger-sized in tablet mode. Typing searches as usual;
// clearing the text brings the grid back.
//
//      ╭────────────────────────────────────────────────────────╮
//      │ (⌕)  Search apps…                                ▦ esc │
//      │ [All] [Internet] [Media] [Office] [Games] [System] …   │
//      ├────────────────────────────────────────────────────────┤
//      │   (🦊)      (💬)      (🎵)      (📁)      (⌨)      (⚙)   │
//      │  Firefox  Discord  Spotify   Files   Terminal Settings │
//      ╰────────────────────────────────────────────────────────╯
//
// Plain QtQuick, so it can be previewed outside the shell.
Item {
    id: root

    // Width of the middle island right now: where we start and end.
    property real startWidth: 200
    property bool open: false
    // What's typed, for writing; the search reads `typed`: the text with
    // the word an input method is still composing (fcitx5's preedit), so
    // results come while you type Vietnamese, not only after Space.
    property alias query: input.text
    readonly property string typed: input.displayText
    property int selected: 0

    // The screen's size (the window's own is 100 x 100 for a moment when
    // it's made, which would make the grid's card jump).
    property real screenWidth: width
    property real screenHeight: height

    // While true the bar hides the real middle island.
    readonly property bool covering: morph.covering
    // Fully back in the island: the window can go.
    readonly property bool settled: morph.settled
    readonly property alias cardItem: morph.card

    // Settings rows too ("dock" -> Settings › Dock › …); Enter opens the
    // Settings window there. Sections.qml is only read once you type.
    readonly property var results: Apps.results(typed, text => SettingsSearch.launcherResults(text, 4))
    readonly property string mode: Apps.modeOf(typed)
    readonly property real searchHeight: 52

    // Emoji show as a grid of big glyphs, everything else as rows.
    readonly property bool gridMode: mode === "emoji" && results.length > 0 && results[0].kind === "emoji"
    readonly property real cellWidth: (Style.launcherWidth - 16) / gridCols
    readonly property int gridCols: Math.max(4, Math.floor((Style.launcherWidth - 16) / 52))
    readonly property int gridRows: gridMode ? Math.min(5, Math.ceil(results.length / gridCols)) : 0
    readonly property real cellHeight: 52
    readonly property real nameHeight: 30
    readonly property int shownRows: gridMode || appGrid ? 0 : Math.min(Style.launcherRows, results.length)

    // The chips under the search field when nothing is typed.
    readonly property var modes: [
        { sign: ":", label: "Emoji", icon: "mood", on: Style.launcherEmoji },
        { sign: "/", label: "Files", icon: "folder_open", on: Style.launcherFiles },
        { sign: "?", label: "Web", icon: "travel_explore", on: Style.launcherWeb },
        { sign: "tr", insert: "tr ", label: "Translate", icon: "translate", on: Style.launcherTranslate }
    ].filter(m => m.on)
    readonly property bool showHints: typed === "" && !appGrid
    readonly property real hintsHeight: showHints ? 40 : 0
    readonly property var modeInfo: ({
        emoji: { label: "Emoji", icon: "mood" },
        files: { label: "Files", icon: "folder_open" },
        web: { label: "Web", icon: "travel_explore" },
        translate: { label: "Translate", icon: "translate" }
    })[mode] ?? null
    readonly property real resultsTop: searchHeight + hintsHeight

    // ---- The app grid (AppGrid.qml) ------------------------------------------------
    readonly property bool appGrid: LauncherState.grid && typed === ""
    // Made the first time it shows, then kept while the launcher is open
    // (typing only hides it).
    property bool gridMade: false
    onAppGridChanged: if (appGrid) gridMade = true
    Component.onCompleted: if (appGrid) gridMade = true
    readonly property bool tablet: TabletMode.tablet
    readonly property real gridIcon: Math.round(Style.launcherGridIconSize * (tablet ? 1.2 : 1))
    readonly property real tileWidth: gridIcon + 56
    readonly property real tileHeight: gridIcon + 52
    // Room left at the screen's sides and under the card (the dock, or the
    // on-screen keyboard).
    readonly property real gridSide: tablet ? 16 : 40
    readonly property real gridBottom: OskState.open ? Style.oskHeight + 12
        : tablet ? 16 : Style.dockMarginEdge + Style.dockIconSize + 2 * Style.dockPaddingCross + 16
    readonly property int tileCols: Math.max(3, Math.min(tablet ? 12 : 8, Math.floor((screenWidth - 2 * gridSide - 24) / tileWidth)))
    // A tablet gets the whole screen; a laptop a card as wide as the columns.
    readonly property real gridCardWidth: Math.max(Style.launcherWidth,
        tablet ? screenWidth - 2 * gridSide : tileCols * tileWidth + 24)
    readonly property real gridTop: searchHeight + 44
    readonly property real gridCardHeight: Math.min(screenHeight - Style.marginEdge - gridBottom,
        gridTop + 5 + Math.max(2, Math.ceil(Apps.gridApps.length / tileCols)) * tileHeight + 8)
    // The card's width eases when the grid comes or goes while it's open.
    property real cardWidth: appGrid ? gridCardWidth : Style.launcherWidth
    Behavior on cardWidth {
        enabled: morph.revealed
        NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
    }

    // The ▦ button: the grid on (the text goes) or off.
    function toggleGrid() {
        if (appGrid) {
            LauncherState.setGrid(false);
        } else {
            query = "";
            LauncherState.setGrid(true);
        }
        focusSearch();
    }

    // The grid's keys (the search field has the focus): true when taken.
    function gridKey(event) {
        const g = appGridLoader.item;
        if (!g)
            return false;
        const shift = event.modifiers & Qt.ShiftModifier;
        switch (event.key) {
        case Qt.Key_Right: g.move(1); return true;
        case Qt.Key_Left: g.move(-1); return true;
        case Qt.Key_Down: g.moveRows(1); return true;
        case Qt.Key_Up: g.moveRows(-1); return true;
        case Qt.Key_PageDown: g.moveRows(3); return true;
        case Qt.Key_PageUp: g.moveRows(-3); return true;
        case Qt.Key_Tab: g.moveGroup(1); return true;
        case Qt.Key_Backtab: g.moveGroup(-1); return true;
        case Qt.Key_Return:
        case Qt.Key_Enter: g.openSelected(); return true;
        case Qt.Key_Menu: g.menuFor(g.selected); return true;
        case Qt.Key_F10:
            if (!shift)
                return false;
            g.menuFor(g.selected);
            return true;
        }
        return false;
    }

    signal closeRequested()

    function focusSearch() {
        input.forceActiveFocus();
    }

    function move(by) {
        if (results.length === 0)
            return;
        selected = Math.max(0, Math.min(results.length - 1, selected + by));
        if (gridMode)
            grid.positionViewAtIndex(selected, GridView.Contain);
        else
            list.positionViewAtIndex(selected, ListView.Contain);
    }

    // The app menu of a result row (AppMenu): false if it isn't an app.
    function openRowMenu(index) {
        const r = results[index];
        if (r?.kind !== "app")
            return false;
        selected = index;
        list.positionViewAtIndex(index, ListView.Contain);
        const row = list.itemAtIndex(index);
        const top = list.y + (row ? row.y - list.contentY : 0);
        appMenu.openFor(r.entry, Qt.rect(list.x, top, list.width - 8, Style.launcherRowHeight), true);
        return true;
    }

    // `inFolder`: Ctrl+Enter (a file's folder).
    function choose(index, inFolder) {
        const r = results[index];
        if (!r)
            return;
        if (Apps.run(r, inFolder))
            closeRequested();
    }

    // New text: back to the best match.
    onTypedChanged: {
        appMenu.close();
        Apps.prepare(typed);
        selected = 0;
        list.positionViewAtBeginning();
        grid.positionViewAtBeginning();
        spin.rotation += 40;
    }
    // Closed: stop a file search that may still run, and a translation
    // (nothing goes out after Esc).
    onOpenChanged: if (!open) {
        Apps.prepare("");
        appMenu.close();
    }
    Component.onDestruction: Apps.prepare("")

    MorphCard {
        id: morph

        anchors.fill: parent
        fromX: (width - root.startWidth) / 2
        fromY: Style.islandTop
        fromWidth: root.startWidth
        toWidth: root.cardWidth
        toHeight: root.appGrid ? root.gridCardHeight : Math.max(root.resultsTop
                  + (root.shownRows > 0 ? 9 + root.shownRows * Style.launcherRowHeight + 8 : 0)
                  + (root.gridRows > 0 ? 9 + root.gridRows * root.cellHeight + root.nameHeight + 8 : 0),
                  // An app's menu under its row: the card grows for it.
                  appMenu.shown ? appMenu.y + appMenu.height + 10 : 0)
        radius: Style.launcherRadius
        glassOpacity: Style.launcherOpacity
        open: root.open

        // Clicks on the card stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        // ---- Search row ---------------------------------------------------------
        Item {
            id: search
            width: root.cardWidth
            height: root.searchHeight

            // A cookie that turns a little with every key.
            Item {
                id: badge
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32

                Shape {
                    id: spin
                    anchors.fill: parent
                    shape: "Cookie9Sided"
                    color: Colors.primary
                    Behavior on rotation {
                        NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                    }
                }
                Icon {
                    anchors.centerIn: parent
                    name: root.modeInfo?.icon ?? "search"
                    size: 18
                    color: Colors.textOnPrimary
                }
            }

            TextInput {
                id: input
                anchors.left: badge.right
                anchors.leftMargin: 12
                anchors.right: modeChip.visible ? modeChip.left : gridButton.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                color: Colors.textOnSurface
                selectionColor: Style.alpha(Colors.primary, 0.4)
                selectedTextColor: Colors.textOnSurface
                font.family: Style.font
                font.pixelSize: Style.textSize("headline")
                font.variableAxes: ({ "wght": 500, "ROND": 100 })
                clip: true

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search apps, settings, 2+3*4, or a web address"
                    font.pixelSize: Style.textSize("headline")
                    color: Colors.textOnSurfaceVariant
                    opacity: 0.7
                    visible: root.typed === ""
                }

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    // An app's menu is open: its keys first.
                    if (appMenu.shown && appMenu.key(event)) {
                        event.accepted = true;
                        return;
                    }
                    const atEnd = input.cursorPosition === input.length && input.preeditText === "";
                    if (event.key === Qt.Key_Escape) {
                        root.closeRequested();
                    } else if (root.appGrid && root.gridKey(event)) {
                        // taken by the app grid
                    } else if (root.gridMode && (event.key === Qt.Key_Right || event.key === Qt.Key_Left)) {
                        root.move(event.key === Qt.Key_Right ? 1 : -1);
                    } else if (root.gridMode && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
                        root.move(event.key === Qt.Key_Down ? root.gridCols : -root.gridCols);
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))) {
                        root.move(1);
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))) {
                        root.move(-1);
                    } else if (event.key === Qt.Key_PageDown) {
                        root.move(Style.launcherRows);
                    } else if (event.key === Qt.Key_PageUp) {
                        root.move(-Style.launcherRows);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.choose(root.selected, ctrl);
                    } else if ((event.key === Qt.Key_Right && atEnd) || event.key === Qt.Key_Menu
                               || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                        if (!root.openRowMenu(root.selected))
                            return;
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }

            // The mode a sign picked (":" Emoji, "/" Files, "?" Web).
            Rectangle {
                id: modeChip
                anchors.right: gridButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: root.modeInfo !== null
                width: modeRow.implicitWidth + 18
                height: 26
                radius: 13
                color: Colors.secondaryContainer

                Row {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: 5

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.modeInfo?.icon ?? ""
                        size: 15
                        color: Colors.textOnSecondaryContainer
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.modeInfo?.label ?? ""
                        role: "label"
                        color: Colors.textOnSecondaryContainer
                    }
                }
            }

            // ▦: the app grid on / off.
            Rectangle {
                id: gridButton
                anchors.right: hint.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: 10
                color: root.appGrid ? Style.alpha(Colors.primary, 0.18)
                     : Style.alpha(Colors.textOnSurface, gridHover.hovered ? 0.1 : 0)
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Icon {
                    anchors.centerIn: parent
                    name: "apps"
                    size: 19
                    color: root.appGrid ? Colors.primary : Colors.textOnSurfaceVariant
                }
                HoverHandler {
                    id: gridHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: root.toggleGrid()
                }
            }

            // "esc" key hint; a tap on it closes too. In tablet mode it's a
            // finger-sized ✕: the keyboard is off there, and the grid's card
            // leaves little room around it to tap.
            Rectangle {
                id: hint
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: root.tablet ? 36 : hintText.implicitWidth + 14
                height: root.tablet ? 36 : 22
                radius: root.tablet ? 18 : 7
                color: Style.alpha(Colors.textOnSurface, hintHover.hovered ? 0.1 : 0)
                border.width: 1
                border.color: Style.alpha(Colors.textOnSurface, 0.18)

                StyledText {
                    id: hintText
                    anchors.centerIn: parent
                    visible: !root.tablet
                    text: "esc"
                    role: "micro"
                    color: Colors.textOnSurfaceVariant
                }
                Icon {
                    anchors.centerIn: parent
                    visible: root.tablet
                    name: "close"
                    size: 20
                    color: Colors.textOnSurfaceVariant
                }
                HoverHandler {
                    id: hintHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: root.closeRequested()
                }
            }
        }

        // ---- The modes, while nothing is typed ------------------------------
        Row {
            x: 16
            y: root.searchHeight + 2
            height: 32
            spacing: 6
            visible: root.showHints
            opacity: root.showHints ? 1 : 0

            Repeater {
                model: root.modes

                HintChip {
                    required property var modelData
                    sign: modelData.sign
                    label: modelData.label
                    icon: modelData.icon
                    onPicked: {
                        root.query = modelData.insert ?? modelData.sign;
                        root.focusSearch();
                    }
                }
            }
            HintChip {
                sign: "2+3"
                label: "Math"
                icon: "calculate"
                clickable: false
            }
        }

        Rectangle {
            x: 16
            y: root.resultsTop
            width: Style.launcherWidth - 32
            height: 1
            color: Style.alpha(Colors.textOnSurface, 0.1)
            visible: (root.shownRows > 0 || root.gridRows > 0) && !root.appGrid
        }

        // ---- Results --------------------------------------------------------------
        ListView {
            id: list

            x: 8
            y: root.resultsTop + 9
            width: Style.launcherWidth - 16
            height: root.shownRows * Style.launcherRowHeight
            visible: !root.gridMode && !root.appGrid
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.gridMode || root.appGrid ? [] : root.results
            currentIndex: root.selected
            highlightFollowsCurrentItem: false

            // The selection pill slides from row to row.
            highlight: Rectangle {
                width: list.width
                height: Style.launcherRowHeight
                y: list.currentItem?.y ?? 0
                radius: Style.inner(Style.launcherRadius, list.x)
                color: Style.alpha(Colors.primary, 0.16)
                // Nothing to pick on a hint row ("Searching…").
                opacity: root.results[root.selected]?.kind === "hint" ? 0 : 1

                Behavior on y {
                    NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }
            }

            delegate: ResultRow {
                selected: index === root.selected
                actionsHint: selected && modelData.kind === "app" && !appMenu.shown
                onHoveredRow: i => {
                    if (!appMenu.shown)
                        root.selected = i;
                }
                onChosen: i => root.choose(i, false)
                onMenuRequested: i => root.openRowMenu(i)
            }
        }

        // ---- Emoji grid --------------------------------------------------------------
        GridView {
            id: grid

            x: 8
            y: root.resultsTop + 9
            width: Style.launcherWidth - 16
            height: root.gridRows * root.cellHeight
            visible: root.gridMode
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            model: root.gridMode ? root.results : []
            currentIndex: root.gridMode ? root.selected : -1

            delegate: EmojiCell {
                width: root.cellWidth
                height: root.cellHeight
                selected: index === root.selected
                onHoveredCell: i => root.selected = i
                onChosen: i => root.choose(i, false)
            }
        }

        // The selected emoji's name.
        Row {
            x: 20
            y: root.resultsTop + 9 + root.gridRows * root.cellHeight + 4
            height: root.nameHeight - 4
            spacing: 8
            visible: root.gridMode

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.gridMode ? (root.results[root.selected]?.subtitle ?? "") : ""
                role: "body"
                weight: 650
                color: Colors.textOnSurface
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "·  Enter copies it"
                role: "caption"
                color: Colors.textOnSurfaceVariant
            }
        }

        // ---- The app grid -------------------------------------------------------------
        Loader {
            id: appGridLoader
            x: 12
            y: root.searchHeight
            // Its final size, so the tiles don't re-lay out while the card grows.
            width: root.gridCardWidth - 24
            height: root.gridCardHeight - root.searchHeight - 6
            active: root.gridMade
            // Made in the background (~100 ms of tiles and icons), so the
            // window opens as fast as the plain launcher; it fades in when
            // it's there (sandbox: key → opening ~125 ms, both ways).
            asynchronous: true
            visible: root.appGrid
            opacity: root.appGrid ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            }

            sourceComponent: AppGrid {
                iconSize: root.gridIcon
                tileWidth: root.tileWidth
                tileHeight: root.tileHeight
                frozen: appMenu.shown
                onChosen: entry => {
                    if (Apps.run(Apps.appResult(entry), false))
                        root.closeRequested();
                }
                onMenuRequested: (entry, tile) => {
                    const p = tile.mapToItem(appMenu.parent, 0, 0);
                    appMenu.openFor(entry, Qt.rect(p.x, p.y + 4, tile.width, tile.height - 8), false);
                }
            }
        }

        // ---- An app's menu (AppMenu) -------------------------------------------------
        // A click anywhere else on the card closes it.
        MouseArea {
            anchors.fill: parent
            visible: appMenu.shown
            acceptedButtons: Qt.AllButtons
            onPressed: appMenu.close()
        }

        AppMenu {
            id: appMenu
            roomWidth: root.cardWidth
            // A row's menu goes below it (the card grows); a tile's stays
            // inside the grid's card.
            roomHeight: root.appGrid ? root.gridCardHeight : root.screenHeight
            onRan: root.closeRequested()
        }
    }
}
