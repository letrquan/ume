import QtQuick
import qs.common
import qs.services

// The clipboard history. Like the launcher it grows out of the middle
// island (MorphCard), here into a search field over your copied things,
// newest first.
//
//      ╭──────────────────────────────────────────────────╮
//      │ (⧉)  filter…                         12  Clear   │
//      ├──────────────────────────────────────────────────┤
//      │ ▌(¶) some copied text…                        ✕ │ ← selected
//      │  [picture]  Picture · png · 896x515              │
//      ╰──────────────────────────────────────────────────╯
//
// Type to filter, ↑↓ to move, Enter: paste into the app you were in,
// Shift+Enter: only copy, Delete: forget it, Esc: close.
// Plain QtQuick (plus Clipboard), so it can be previewed outside the shell.
Item {
    id: root

    // Width of the middle island right now: where we start and end.
    property real startWidth: 200
    property bool open: false
    // Includes the word the IME is still composing.
    readonly property string query: input.displayText
    property int selected: 0

    // While true the bar hides the real middle island.
    readonly property bool covering: morph.covering
    // Fully back in the island: the window can go.
    readonly property bool settled: morph.settled
    readonly property alias cardItem: morph.card

    readonly property var items: {
        const q = query.trim().toLowerCase();
        return q === "" ? Clipboard.entries : Clipboard.entries.filter(e => e.text.toLowerCase().includes(q));
    }
    readonly property real listHeight: {
        let h = 0;
        for (let i = 0; i < Math.min(items.length, Style.clipRows); i++)
            h += items[i].image ? Style.clipRowHeight + 30 : Style.clipRowHeight;
        return h;
    }
    readonly property real searchHeight: 52

    signal closeRequested()

    function focusSearch() {
        input.forceActiveFocus();
    }

    function move(by) {
        if (items.length === 0)
            return;
        selected = Math.max(0, Math.min(items.length - 1, selected + by));
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    function choose(index, paste) {
        const e = items[index];
        if (!e)
            return;
        closeRequested();
        Clipboard.use(e, paste);
    }

    function forget(index) {
        const e = items[index];
        if (!e)
            return;
        Clipboard.remove(e);
        selected = Math.min(selected, items.length - 1);
    }

    onQueryChanged: {
        selected = 0;
        list.positionViewAtBeginning();
    }
    onOpenChanged: if (open) Clipboard.refresh()

    // Clear asks twice: the first press arms it for a few seconds.
    property bool clearArmed: false
    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.clearArmed = false
    }

    MorphCard {
        id: morph

        anchors.fill: parent
        fromX: (width - root.startWidth) / 2
        fromY: Style.islandTop
        fromWidth: root.startWidth
        toWidth: Style.clipWidth
        toHeight: root.searchHeight + (root.items.length > 0 ? 9 + root.listHeight + 8 : empty.implicitHeight)
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
            width: Style.clipWidth
            height: root.searchHeight

            Item {
                id: badge
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32

                Shape {
                    anchors.fill: parent
                    shape: "Cookie4Sided"
                    color: Colors.primary
                }
                Icon {
                    anchors.centerIn: parent
                    name: "content_paste"
                    size: 18
                    color: Colors.textOnPrimary
                }
            }

            TextInput {
                id: input
                anchors.left: badge.right
                anchors.leftMargin: 12
                anchors.right: tools.left
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
                    text: "Search your clipboard"
                    font.pixelSize: Style.textSize("headline")
                    color: Colors.textOnSurfaceVariant
                    opacity: 0.7
                    visible: input.displayText === ""
                }

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const shift = event.modifiers & Qt.ShiftModifier;
                    if (event.key === Qt.Key_Escape) {
                        root.closeRequested();
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))) {
                        root.move(1);
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))) {
                        root.move(-1);
                    } else if (event.key === Qt.Key_PageDown) {
                        root.move(Style.clipRows);
                    } else if (event.key === Qt.Key_PageUp) {
                        root.move(-Style.clipRows);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.choose(root.selected, !shift);
                    } else if (event.key === Qt.Key_Delete) {
                        root.forget(root.selected);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }

            Row {
                id: tools
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.items.length
                    visible: root.items.length > 0
                    rightPadding: 4
                    role: "caption"
                    font.features: ({ "tnum": 1 })
                    color: Colors.textOnSurfaceVariant
                }

                // Clear all: press twice.
                Clickable {
                    implicitHeight: 30
                    padding: 10
                    visible: Clipboard.entries.length > 0
                    onClicked: {
                        if (root.clearArmed) {
                            Clipboard.wipe();
                            root.clearArmed = false;
                        } else {
                            root.clearArmed = true;
                            disarm.restart();
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.clearArmed ? "Press again to clear" : "Clear"
                        role: "label"
                        color: root.clearArmed ? Colors.error : Colors.textOnSurfaceVariant
                    }
                }
            }
        }

        Rectangle {
            x: 16
            y: root.searchHeight
            width: Style.clipWidth - 32
            height: 1
            color: Style.alpha(Colors.textOnSurface, 0.1)
        }

        // Nothing (yet) or no match.
        EmptyState {
            id: empty
            x: (Style.clipWidth - width) / 2
            y: root.searchHeight
            visible: root.items.length === 0
            active: morph.revealed
            shape: root.query !== "" ? "Clover4Leaf" : "Cookie9Sided"
            icon: Clipboard.loading ? "hourglass_empty" : root.query !== "" ? "search_off" : "content_paste_off"
            title: Clipboard.loading ? "Loading…" : root.query !== "" ? "Nothing matches" : "Nothing copied yet"
            hint: Clipboard.loading ? "" : root.query !== "" ? "Nothing you copied has “" + root.query.trim() + "” in it"
                                                            : "Copy something and it shows up here"
        }

        // ---- Entries ------------------------------------------------------------------
        ListView {
            id: list

            x: 8
            y: root.searchHeight + 9
            width: Style.clipWidth - 16
            height: Math.min(contentHeight, root.listHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.items
            currentIndex: root.selected
            highlightFollowsCurrentItem: false

            // The selection pill slides from row to row.
            highlight: Rectangle {
                width: list.width
                height: list.currentItem?.height ?? Style.clipRowHeight
                y: list.currentItem?.y ?? 0
                radius: Style.inner(Style.launcherRadius, list.x)
                color: Style.alpha(Colors.primary, 0.16)

                Behavior on y {
                    NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }
                Behavior on height {
                    NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }
            }

            delegate: ClipRow {
                selected: index === root.selected
                onHoveredRow: i => root.selected = i
                onChosen: (i, paste) => root.choose(i, paste)
                onRemoved: i => root.forget(i)
            }
        }
    }
}
