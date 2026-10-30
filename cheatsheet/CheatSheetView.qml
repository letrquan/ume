import QtQuick
import qs.common
import qs.services

// The cheat sheet: the screen dims, a wide glass card springs up in the
// middle with every mango shortcut in titled groups, in columns. Type to
// filter; Esc clears the search, then closes.
//
//   ╭──────────────────────────────────────────────────────────────────╮
//   │ (⌨) Keyboard shortcuts                       ( 🔍 Search…      ) │
//   │     52 shortcuts · from mango's config                           │
//   │  ╭ Apps ───────────────╮ ╭ Workspaces ────────╮ ╭ Shell ──────╮  │
//   │  │ Terminal  ⌘Super ↵/T │ │ Go to …   ⌘Super 1–9│ │ Launcher …  │  │
//   │  ╰─────────────────────╯ ╰────────────────────╯ ╰─────────────╯  │
//   ╰──────────────────────────────────────────────────────────────────╯
//
// Plain QtQuick + CheatSheetState, so it can be previewed offscreen.
Item {
    id: root

    property bool open: false
    property string query: ""

    signal closeRequested()

    function focusSearch() {
        input.forceActiveFocus();
    }

    readonly property var shown: CheatSheetState.filtered(query)

    // ---- Columns ---------------------------------------------------------------------
    readonly property int margin: 24
    readonly property int pad: 18
    readonly property int gap: 10
    readonly property int colWidth: Style.cheatSheetColumnWidth
    readonly property int columns: {
        if (Style.cheatSheetColumns > 0)
            return Math.min(Style.cheatSheetColumns, 6);
        const fit = Math.floor((width - 2 * margin - 2 * pad + gap) / (colWidth + gap));
        return Math.max(1, Math.min(4, fit));
    }

    // About how tall a group is (header + rows + padding, as ShortcutGroup).
    function groupHeight(g) {
        return 28 + g.rows.length * Style.cheatSheetRowHeight + 16;
    }

    // Groups in reading order, cut into `columns` runs as even as can be
    // (the tallest column as short as possible): [[{ group, order }], …].
    readonly property var layout: {
        const gs = shown;
        const n = columns;
        const h = gs.map(g => groupHeight(g) + gap);
        const fill = limit => {
            const cols = [[]];
            let used = 0;
            gs.forEach((g, i) => {
                if (used + h[i] > limit && cols[cols.length - 1].length > 0) {
                    cols.push([]);
                    used = 0;
                }
                cols[cols.length - 1].push({ group: g, order: i });
                used += h[i];
            });
            return cols;
        };
        // Smallest height that still fits in n columns.
        let lo = Math.max(0, ...h), hi = h.reduce((a, b) => a + b, 0);
        while (lo < hi) {
            const mid = Math.floor((lo + hi) / 2);
            if (fill(mid).length <= n)
                hi = mid;
            else
                lo = mid + 1;
        }
        return fill(lo);
    }
    // The real height (a long description takes two lines).
    readonly property real contentHeight: columnsRow.implicitHeight

    // ---- Coming in: the groups follow each other up ----------------------------------
    property real reveal: 0
    readonly property int revealStep: 35       // ms between groups
    readonly property int revealEach: 380      // ms for one group
    readonly property int revealTotal: revealEach + revealStep * Math.max(0, shown.length - 1)

    function shownOf(order) {
        const t = Math.max(0, Math.min(1, (reveal * revealTotal - order * revealStep) / revealEach));
        return 1 - Math.pow(1 - t, 3);
    }

    NumberAnimation {
        id: revealAnim
        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: root.revealTotal
    }

    onOpenChanged: {
        if (open) {
            query = "";
            input.text = "";
            reveal = 0;
            revealAnim.restart();
            scroll.contentY = 0;
        }
    }

    // ---- Keys ---------------------------------------------------------------------------
    function scrollBy(dy) {
        scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, scroll.contentY + dy));
    }

    // ---- Dim the screen -----------------------------------------------------------------
    // The blurred wallpaper and the dim, fading together (Backdrop).
    Backdrop {
        anchors.fill: parent
        shown: root.open
        dim: Style.cheatSheetDim
    }

    // ---- The card -----------------------------------------------------------------------
    Item {
        id: card

        // Title, the 14 px under it, the groups, padding above and below.
        // (Room for the empty state too, when nothing matches.)
        readonly property real fullHeight: header.height + 14 + Math.max(root.contentHeight, empty.visible ? empty.implicitHeight : 0) + root.pad * 2

        anchors.centerIn: parent
        width: root.columns * root.colWidth + (root.columns - 1) * root.gap + root.pad * 2
        height: Math.max(header.height + 120, Math.min(root.height - root.margin * 2, fullHeight))
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.94

        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
        }
        Behavior on height {
            NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
        }

        // Darkening off: no backdrop, so the card frosts its own piece.
        WallpaperFrost {
            anchors.fill: parent
            at: Qt.point(card.x, card.y)
            radius: Style.cheatSheetRadius
            visible: Style.cheatSheetDim <= 0
        }
        Glass {
            anchors.fill: parent
            radius: Style.cheatSheetRadius
            color: Style.alpha(Colors.surfaceContainer, Style.cheatSheetOpacity)
        }

        // Clicks on the card stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        // ---- Title and search ----------------------------------------------------------
        Item {
            id: header
            x: root.pad
            y: root.pad
            width: parent.width - root.pad * 2
            height: 48

            Item {
                id: badge
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40

                Shape {
                    anchors.fill: parent
                    shape: "Cookie7Sided"
                    color: Colors.primary
                }
                Icon {
                    anchors.centerIn: parent
                    name: "keyboard"
                    size: 21
                    color: Colors.textOnPrimary
                }
            }

            Column {
                anchors.left: badge.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                StyledText {
                    text: "Keyboard shortcuts"
                    role: "headline"
                }
                StyledText {
                    text: !CheatSheetState.loaded ? "Reading mango's config…"
                        : root.query === "" ? CheatSheetState.count + " shortcuts · from mango's config"
                        : root.shown.reduce((n, g) => n + g.rows.length, 0) + " of " + CheatSheetState.count + " shortcuts"
                    role: "caption"
                    color: Colors.textOnSurfaceVariant
                }
            }

            // The search field.
            Rectangle {
                id: field
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(300, parent.width / 2)
                height: 40
                radius: height / 2
                color: Style.alpha(Colors.textOnSurface, input.activeFocus ? 0.09 : 0.06)
                border.width: 1
                border.color: Style.alpha(Colors.textOnSurface, 0.08)

                Icon {
                    id: lens
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 19
                    color: Colors.textOnSurfaceVariant
                }

                TextInput {
                    id: input
                    anchors.left: lens.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: Colors.textOnSurface
                    selectionColor: Style.alpha(Colors.primary, 0.4)
                    selectedTextColor: Colors.textOnSurface
                    font.family: Style.font
                    font.pixelSize: Style.textSize("body")
                    font.variableAxes: ({ "wght": 500, "ROND": 100 })
                    clip: true
                    // displayText: with the word the IME is still composing.
                    onDisplayTextChanged: {
                        root.query = displayText;
                        scroll.contentY = 0;
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search shortcuts"
                        font.pixelSize: Style.textSize("body")
                        color: Colors.textOnSurfaceVariant
                        opacity: 0.7
                        visible: input.displayText === ""
                    }

                    Keys.onPressed: event => {
                        const k = event.key;
                        if (k === Qt.Key_Escape) {
                            if (input.text !== "")
                                input.text = "";
                            else
                                root.closeRequested();
                        } else if (k === Qt.Key_Down) {
                            root.scrollBy(Style.cheatSheetRowHeight * 3);
                        } else if (k === Qt.Key_Up) {
                            root.scrollBy(-Style.cheatSheetRowHeight * 3);
                        } else if (k === Qt.Key_PageDown) {
                            root.scrollBy(scroll.height * 0.8);
                        } else if (k === Qt.Key_PageUp) {
                            root.scrollBy(-scroll.height * 0.8);
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }
            }
        }

        // ---- The groups ----------------------------------------------------------------
        Flickable {
            id: scroll
            x: root.pad
            anchors.top: header.bottom
            anchors.topMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.pad
            width: parent.width - root.pad * 2
            contentHeight: root.contentHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: columnsRow
                spacing: root.gap

                Repeater {
                    model: root.layout

                    Column {
                        id: col
                        required property var modelData

                        width: root.colWidth
                        spacing: root.gap

                        Repeater {
                            model: col.modelData

                            ShortcutGroup {
                                required property var modelData
                                width: col.width
                                group: modelData.group
                                shown: root.shownOf(modelData.order)
                            }
                        }
                    }
                }
            }
        }

        // More below: the list fades out at the bottom edge.
        Rectangle {
            anchors.left: scroll.left
            anchors.right: scroll.right
            anchors.bottom: scroll.bottom
            height: 36
            opacity: scroll.contentY < scroll.contentHeight - scroll.height - 2 ? 1 : 0
            gradient: Gradient {
                GradientStop { position: 0; color: Style.alpha(Colors.surfaceContainer, 0) }
                GradientStop { position: 1; color: Style.alpha(Colors.surfaceContainer, Math.min(1, Style.cheatSheetOpacity + 0.1)) }
            }
            Behavior on opacity {
                NumberAnimation { duration: Motion.fast }
            }
        }

        EmptyState {
            id: empty
            anchors.centerIn: scroll
            visible: CheatSheetState.loaded && root.shown.length === 0
            active: root.open
            textWidth: 420
            shape: root.query !== "" ? "Clover4Leaf" : "Cookie9Sided"
            icon: root.query !== "" ? "search_off" : "keyboard_off"
            title: root.query !== "" ? "Nothing matches “" + root.query + "”" : "No shortcuts found"
            hint: root.query !== "" ? "Try a key (Super, Print) or a word from what it does"
                : "Looked in " + CheatSheetState.configPath
        }
    }
}
