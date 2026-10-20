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
// Tab to move, Enter to open, Esc to close. A sign first picks a mode, shown
// in a chip by the search field: ":" emoji (a grid; ←→↑↓ move, Enter copies),
// "/" or "~" files (Ctrl+Enter opens the folder), "?" the web. With nothing
// typed, a row of chips lists them. Plain QtQuick, so it can be previewed
// outside the shell.
Item {
    id: root

    // Width of the middle island right now: where we start and end.
    property real startWidth: 200
    property bool open: false
    property alias query: input.text
    property int selected: 0

    // While true the bar hides the real middle island.
    readonly property bool covering: morph.covering
    // Fully back in the island: the window can go.
    readonly property bool settled: morph.settled
    readonly property alias cardItem: morph.card

    // Settings rows too ("dock" -> Settings › Dock › …); Enter opens the
    // Settings window there. Sections.qml is only read once you type.
    readonly property var results: Apps.results(query, text => SettingsSearch.launcherResults(text, 4))
    readonly property string mode: Apps.modeOf(query)
    readonly property real searchHeight: 52

    // Emoji show as a grid of big glyphs, everything else as rows.
    readonly property bool gridMode: mode === "emoji" && results.length > 0 && results[0].kind === "emoji"
    readonly property real cellWidth: (Style.launcherWidth - 16) / gridCols
    readonly property int gridCols: Math.max(4, Math.floor((Style.launcherWidth - 16) / 52))
    readonly property int gridRows: gridMode ? Math.min(5, Math.ceil(results.length / gridCols)) : 0
    readonly property real cellHeight: 52
    readonly property real nameHeight: 30
    readonly property int shownRows: gridMode ? 0 : Math.min(Style.launcherRows, results.length)

    // The chips under the search field when nothing is typed.
    readonly property var modes: [
        { sign: ":", label: "Emoji", icon: "mood", on: Style.launcherEmoji },
        { sign: "/", label: "Files", icon: "folder_open", on: Style.launcherFiles },
        { sign: "?", label: "Web", icon: "travel_explore", on: Style.launcherWeb }
    ].filter(m => m.on)
    readonly property bool showHints: query === ""
    readonly property real hintsHeight: showHints ? 40 : 0
    readonly property var modeInfo: ({
        emoji: { label: "Emoji", icon: "mood" },
        files: { label: "Files", icon: "folder_open" },
        web: { label: "Web", icon: "travel_explore" }
    })[mode] ?? null
    readonly property real resultsTop: searchHeight + hintsHeight

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

    // `inFolder`: Ctrl+Enter (a file's folder).
    function choose(index, inFolder) {
        const r = results[index];
        if (!r)
            return;
        if (Apps.run(r, inFolder))
            closeRequested();
    }

    // New text: back to the best match.
    onQueryChanged: {
        Apps.prepare(query);
        selected = 0;
        list.positionViewAtBeginning();
        grid.positionViewAtBeginning();
        spin.rotation += 40;
    }
    // Closed: stop a file search that may still run.
    onOpenChanged: if (!open) FileSearch.search("")

    MorphCard {
        id: morph

        anchors.fill: parent
        fromX: (width - root.startWidth) / 2
        fromY: Style.marginEdge
        fromWidth: root.startWidth
        toWidth: Style.launcherWidth
        toHeight: root.resultsTop
                  + (root.shownRows > 0 ? 9 + root.shownRows * Style.launcherRowHeight + 8 : 0)
                  + (root.gridRows > 0 ? 9 + root.gridRows * root.cellHeight + root.nameHeight + 8 : 0)
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
            width: Style.launcherWidth
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
                anchors.right: modeChip.visible ? modeChip.left : hint.left
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
                    visible: input.text === ""
                }

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    if (event.key === Qt.Key_Escape) {
                        root.closeRequested();
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
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }

            // The mode a sign picked (":" Emoji, "/" Files, "?" Web).
            Rectangle {
                id: modeChip
                anchors.right: hint.left
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

            // "esc" key hint.
            Rectangle {
                id: hint
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: hintText.implicitWidth + 14
                height: 22
                radius: 7
                color: "transparent"
                border.width: 1
                border.color: Style.alpha(Colors.textOnSurface, 0.18)

                StyledText {
                    id: hintText
                    anchors.centerIn: parent
                    text: "esc"
                    role: "micro"
                    color: Colors.textOnSurfaceVariant
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
                        root.query = modelData.sign;
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
            visible: root.shownRows > 0 || root.gridRows > 0
        }

        // ---- Results --------------------------------------------------------------
        ListView {
            id: list

            x: 8
            y: root.resultsTop + 9
            width: Style.launcherWidth - 16
            height: root.shownRows * Style.launcherRowHeight
            visible: !root.gridMode
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.gridMode ? [] : root.results
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
                onHoveredRow: i => root.selected = i
                onChosen: i => root.choose(i, false)
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
    }
}
