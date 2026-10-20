import QtQuick
import qs.common
import qs.services

// The Settings window's content: a glass sidebar of sections on the left
// (each icon on its own colored square, SectionIcon), their settings on the
// right in glass groups. Changes apply at once.
// The field at the top of the sidebar searches every section (names,
// descriptions, section and group titles, knob names; SettingsSearch): the
// matches show on the right and still work there. ↑↓ pick one, Enter (or a
// click on its group's title) shows it in its place, lit up for a moment.
// Keys: ↑↓ (or Ctrl+Tab) move between sections; typing or Ctrl+F searches;
// Esc empties the search, then closes.
// Plain QtQuick, so it can be previewed outside the shell.
FocusScope {
    id: root

    readonly property var sections: Sections.list
    readonly property int selected: Math.max(0, sections.findIndex(s => s.id === SettingsState.section))
    // The section on screen; follows `selected` through a short fade.
    property int shown: selected
    readonly property var section: sections[shown]

    // ---- Search ------------------------------------------------------------------------
    readonly property alias query: searchField.text
    readonly property bool searching: query.trim() !== ""
    readonly property var found: searching ? SettingsSearch.grouped(query) : null
    // What the page shows: the matches, or null for the section. Follows
    // `found` as you type; on the way to a match it changes mid-fade.
    property var results: null
    // The chosen match (↑↓, Enter), counted across the groups.
    property int pick: 0
    property bool jumping: false
    // The setting to keep in view while the page settles (its text wraps
    // again when mango sizes the window), and the one lit up.
    property string pinRef: ""
    property string flashRef: ""

    signal closeRequested()

    // The sidebar floats inside the window, its corners following the
    // window's (mango's); the rows' pill follows the sidebar's.
    readonly property real sideRadius: Style.inner(Style.settingsWindowRadius, Style.settingsInset)
    readonly property real rowRadius: Style.inner(sideRadius, 8)

    function go(by) {
        searchField.text = "";      // another section: the search is over
        const next = (selected + by + sections.length) % sections.length;
        SettingsState.section = sections[next].id;
    }

    onSelectedChanged: swap.restart()
    onFoundChanged: {
        if (jumping)
            return;
        results = found;
        pick = 0;
        pane.contentY = 0;
    }

    function focusSearch() {
        searchField.forceActiveFocus();
    }

    // Show a setting in its place: its section, scrolled to it, lit up.
    // `now`: no fade (the window is just opening).
    function jumpTo(ref, now) {
        const at = SettingsSearch.locate(ref);
        if (!at)
            return;
        pinRef = ref;
        jumping = true;
        searchField.text = "";
        if (now) {
            SettingsState.section = at.section;
            swap.stop();
            settle();
            page.opacity = 1;
            shift.y = 0;
            return;
        }
        if (SettingsState.section !== at.section)
            SettingsState.section = at.section;     // starts the fade
        else
            swap.restart();
    }

    // Mid-fade (or at once): the new page goes in, then the setting wanted
    // is brought into view.
    function settle() {
        results = found;
        jumping = false;
        shown = selected;
        pane.contentY = 0;
        if (pinRef !== "") {
            reveal(true);
            unpin.restart();
        }
    }

    // The row (an item on the page) with this ref, or null.
    function entryFor(ref) {
        for (let i = 0; i < groups.count; i++) {
            const item = groups.itemAt(i)?.entryFor(ref);
            if (item)
                return item;
        }
        return null;
    }

    // The rows' places are worked out before the next frame; this needs them now.
    function layoutNow() {
        for (let i = 0; i < groups.count; i++)
            groups.itemAt(i)?.layoutNow();
        page.forceLayout();
    }

    // Scroll so the pinned row sits in the middle (`first`: and light it up).
    function reveal(first) {
        const item = entryFor(pinRef);
        if (!item) {
            pinRef = "";
            return;
        }
        layoutNow();
        const y = item.mapToItem(page, 0, 0).y + page.y;
        const most = Math.max(0, pane.contentHeight - pane.height);
        pane.contentY = Math.max(0, Math.min(most, y - (pane.height - item.height) / 2));
        if (first) {
            flashRef = pinRef;
            unflash.restart();
        }
    }

    // Keep a match picked with ↑↓ on screen (scrolls only if it isn't).
    function showPicked() {
        const item = entryFor(results?.refs[pick] ?? "");
        if (!item)
            return;
        layoutNow();
        const y = item.mapToItem(page, 0, 0).y + page.y;
        if (y < pane.contentY + 8)
            pane.contentY = Math.max(0, y - 40);
        else if (y + item.height > pane.contentY + pane.height - 8)
            pane.contentY = Math.min(Math.max(0, pane.contentHeight - pane.height), y + item.height - pane.height + 40);
    }

    function movePick(by) {
        if (!results || results.total === 0)
            return;
        pick = Math.max(0, Math.min(results.total - 1, pick + by));
        showPicked();
    }

    // What the launcher or IPC asked for (SettingsState.target / search).
    // Only when the window opens: asking again while it's open reopens it.
    function takeRequest(opening) {
        if (SettingsState.search !== "") {
            const text = SettingsState.search;
            SettingsState.search = "";
            searchField.text = text;
            searchField.cursorPosition = text.length;
        }
        if (SettingsState.target !== "") {
            const ref = SettingsState.target;
            SettingsState.target = "";
            jumpTo(ref, opening);
        }
    }

    // After the rows exist (the pinned one is looked up among them).
    Component.onCompleted: {
        focusSearch();
        Qt.callLater(() => root.takeRequest(true));
    }

    // Light-up ends; the pin lets go (or as soon as you scroll yourself).
    Timer {
        id: unflash
        interval: 2200
        onTriggered: root.flashRef = ""
    }
    Timer {
        id: unpin
        interval: 1500
        onTriggered: root.pinRef = ""
    }

    focus: true
    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Escape && root.searching)
            searchField.text = "";
        else if (event.key === Qt.Key_Escape)
            root.closeRequested();
        else if (ctrl && event.key === Qt.Key_F) {
            root.focusSearch();
            searchField.selectAll();
        } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && ctrl))
            root.go(1);
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
            root.go(-1);
        // Typing anywhere else starts a search.
        else if (!ctrl && !(event.modifiers & Qt.AltModifier) && event.text !== "" && /\S/.test(event.text)
                 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.focusSearch();
            searchField.insert(searchField.cursorPosition, event.text);
        } else
            return;
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Style.alpha(Colors.surface, Style.settingsOpacity)
    }

    // A click on empty space leaves a text field (it keeps what you typed).
    TapHandler {
        onTapped: keySink.forceActiveFocus()
    }
    Item {
        id: keySink
    }

    // ---- Sidebar ------------------------------------------------------------------------
    Item {
        id: sidebar
        x: Style.settingsInset
        y: Style.settingsInset
        width: Style.settingsSidebarWidth
        height: parent.height - Style.settingsInset * 2

        Glass {
            anchors.fill: parent
            radius: root.sideRadius
            color: Style.alpha(Colors.surfaceContainer, Style.settingsSidebarOpacity)
        }

        // The search field.
        Rectangle {
            id: searchBox
            x: 10
            y: 10
            width: parent.width - 20
            height: 34
            radius: height / 2
            color: Style.alpha(Colors.textOnSurface, searchField.activeFocus ? 0.12 : 0.07)
            border.width: searchField.activeFocus ? 2 : 0
            border.color: Colors.primary

            Icon {
                id: searchIcon
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 18
                color: searchField.activeFocus ? Colors.primary : Colors.textOnSurfaceVariant
            }

            TextInput {
                id: searchField
                anchors.left: searchIcon.right
                anchors.leftMargin: 8
                anchors.right: clear.visible ? clear.left : parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: Colors.textOnSurface
                selectionColor: Style.alpha(Colors.primary, 0.4)
                selectedTextColor: Colors.textOnSurface
                font.family: Style.font
                font.pixelSize: Style.textSize("body")
                font.variableAxes: ({ "wght": 500, "ROND": 100 })
                clip: true

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search"
                    font.pixelSize: Style.textSize("body")
                    color: Colors.textOnSurfaceVariant
                    opacity: 0.7
                    visible: searchField.text === ""
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        if (text !== "")
                            text = "";
                        else
                            root.closeRequested();
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                        const by = event.key === Qt.Key_Down ? 1 : -1;
                        if (root.results)
                            root.movePick(by);
                        else
                            root.go(by);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.results && root.results.total > 0)
                            root.jumpTo(root.results.refs[root.pick], false);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }

            // ✕ empties it.
            Clickable {
                id: clear
                anchors.right: parent.right
                anchors.rightMargin: 4
                implicitHeight: 28
                padding: 0
                visible: searchField.text !== ""
                onClicked: {
                    searchField.text = "";
                    root.focusSearch();
                }

                Icon {
                    name: "close"
                    size: 16
                    color: Colors.textOnSurfaceVariant
                }
            }
        }

        Item {
            id: list
            x: 8
            y: 54
            width: parent.width - 16
            height: parent.height - y - 8

            // One section's line: 38 px, less when the window is short.
            readonly property real step: Math.min(38, height / Math.max(1, root.sections.length))

            // The selection pill slides to the chosen section (gone while
            // the page shows search results).
            Rectangle {
                y: root.selected * list.step
                width: parent.width
                height: list.step - 2
                radius: root.rowRadius
                color: Style.alpha(Colors.primary, 0.2)
                opacity: root.results ? 0 : 1

                Behavior on y {
                    NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }

            Repeater {
                model: root.sections

                MouseArea {
                    id: item
                    required property var modelData
                    required property int index
                    readonly property bool current: index === root.selected && !root.results
                    // While searching: how many matches it has (none: dimmed).
                    readonly property int matches: root.results ? (root.results.counts[modelData.id] ?? 0) : -1

                    y: index * list.step
                    width: list.width
                    height: list.step - 2
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    opacity: matches === 0 ? 0.4 : 1
                    onClicked: {
                        searchField.text = "";
                        SettingsState.section = modelData.id;
                    }

                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                    Rectangle {
                        anchors.fill: parent
                        radius: root.rowRadius
                        color: Colors.textOnSurface
                        opacity: !item.current && item.containsMouse ? Style.hoverTint : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Style.settingsSectionColors ? 7 : 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.settingsSectionColors ? 10 : 12

                        SectionIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Style.settingsSectionColors
                            section: item.modelData.id
                            icon: item.modelData.icon
                            size: Math.min(24, list.step - 10)
                            fill: item.current ? 1 : 0
                        }
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !Style.settingsSectionColors
                            name: item.modelData.icon
                            size: 20
                            fill: item.current ? 1 : 0
                            color: item.current ? Colors.primary : Colors.textOnSurfaceVariant
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: item.modelData.title
                            weight: item.current ? 650 : 500
                            color: item.current || Style.settingsSectionColors ? Colors.textOnSurface : Colors.textOnSurfaceVariant
                        }
                    }

                    StyledText {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: item.matches > 0
                        text: String(item.matches)
                        role: "label"
                        font.features: ({ "tnum": 1 })
                        color: Colors.primary
                    }
                }
            }
        }
    }

    // ---- The chosen section (or the search's matches) ------------------------------------
    Flickable {
        id: pane
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        contentHeight: page.implicitHeight + 56
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // You scrolled: stop holding the row in view.
        onMovementStarted: root.pinRef = ""
        onHeightChanged: if (root.pinRef !== "") root.reveal(false)
        onWidthChanged: if (root.pinRef !== "") root.reveal(false)

        Column {
            id: page
            x: 28
            y: 26
            width: pane.width - 56
            spacing: 6
            transform: Translate {
                id: shift
            }

            onImplicitHeightChanged: if (root.pinRef !== "") root.reveal(false)

            // The section's big icon and its name (or what the search found).
            Row {
                width: parent.width
                spacing: 14

                SectionIcon {
                    id: headIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Style.settingsSectionColors
                    section: root.results ? "search" : root.section.id
                    icon: root.results ? "search" : root.section.icon
                    size: 44
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (headIcon.visible ? headIcon.width + parent.spacing : 0)
                    text: !root.results ? root.section.title
                        : root.results.total === 0 ? "Nothing found"
                        : root.results.total + (root.results.total === 1 ? " setting" : " settings")
                    role: "display"
                    elide: Text.ElideRight
                }
            }
            StyledText {
                width: parent.width
                text: !root.results ? root.section.blurb
                    : root.results.total === 0 ? "Nothing matches “" + root.query.trim() + "”. Try a word from a setting's name, like blur, dock or lock."
                    : "Change them right here, or ↑↓ and Enter (or click a group's title) to see one in its place."
                topPadding: 4
                bottomPadding: 14
                color: Colors.textOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            // Rounded groups (a section's `groups`, each with an optional
            // title; or just its `rows`; or the search's matches, by group),
            // thin lines between the rows.
            Repeater {
                id: groups
                model: root.results ? root.results.groups : (root.section.groups ?? [{ title: "", rows: root.section.rows }])

                Column {
                    id: group
                    required property var modelData
                    required property int index
                    readonly property bool isResult: modelData.refs !== undefined
                    width: page.width
                    spacing: 8
                    topPadding: index > 0 ? 18 : 0

                    function entryFor(ref) {
                        for (let i = 0; i < entries.count; i++) {
                            const e = entries.itemAt(i);
                            if (e && e.ref === ref)
                                return e;
                        }
                        return null;
                    }
                    function layoutNow() {
                        rows.forceLayout();
                        group.forceLayout();
                    }

                    // The group's title; a match's "Section › Group" takes you there.
                    MouseArea {
                        id: heading
                        visible: headingText.text !== ""
                        width: headingRow.implicitWidth + 12
                        height: 20
                        enabled: group.isResult
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.jumpTo(group.modelData.refs[0], false)

                        Row {
                            id: headingRow
                            x: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: group.isResult
                                name: group.modelData.icon ?? ""
                                size: 15
                                color: Colors.primary
                            }
                            StyledText {
                                id: headingText
                                anchors.verticalCenter: parent.verticalCenter
                                text: group.modelData.title ?? ""
                                role: "label"
                                font.underline: heading.enabled && heading.containsMouse
                                // A match's heading is a link; a section's is a quiet title.
                                color: group.isResult ? Colors.primary : Colors.textOnSurfaceVariant
                            }
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: group.isResult
                                name: "arrow_forward"
                                size: 15
                                color: Colors.primary
                                opacity: heading.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            }
                        }
                    }

                    Glass {
                        width: parent.width
                        height: rows.implicitHeight
                        radius: Style.settingsCardRadius
                        color: Style.alpha(Colors.surfaceContainer, Style.settingsCardOpacity)

                        Column {
                            id: rows
                            width: parent.width

                            Repeater {
                                id: entries
                                model: group.modelData.rows

                                Item {
                                    id: entry
                                    required property var modelData
                                    required property int index
                                    readonly property string ref: group.isResult ? group.modelData.refs[index]
                                        : SettingsSearch.refOf(root.section, group.modelData, modelData)
                                    // The match chosen with ↑↓; the setting just jumped to.
                                    readonly property bool picked: group.isResult && root.pick === group.modelData.start + index
                                    readonly property bool flashing: root.flashRef !== "" && root.flashRef === ref
                                    property real glow: 0

                                    width: rows.width
                                    height: line.height + settingRow.height

                                    onFlashingChanged: if (flashing) flash.restart()
                                    Component.onCompleted: if (flashing) flash.restart()

                                    SequentialAnimation {
                                        id: flash
                                        NumberAnimation { target: entry; property: "glow"; to: 0.26; duration: 180; easing.type: Easing.OutCubic }
                                        PauseAnimation { duration: 650 }
                                        NumberAnimation { target: entry; property: "glow"; to: 0; duration: 1100; easing.type: Easing.InOutQuad }
                                    }

                                    Rectangle {
                                        id: line
                                        x: 18
                                        width: parent.width - 36
                                        height: entry.index > 0 ? 1 : 0
                                        visible: entry.index > 0
                                        color: Style.alpha(Colors.textOnSurface, 0.08)
                                    }
                                    Rectangle {
                                        x: 4
                                        y: line.height + 3
                                        width: parent.width - 8
                                        height: settingRow.height - 6
                                        radius: Style.inner(Style.settingsCardRadius, 4)
                                        color: Colors.primary
                                        opacity: Math.max(entry.glow, entry.picked ? 0.1 : 0)
                                        visible: opacity > 0.005
                                    }
                                    SettingRow {
                                        id: settingRow
                                        y: line.height
                                        width: parent.width
                                        modelData: entry.modelData
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Changing section: the old one fades up and out, the new one comes in.
    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: page; property: "opacity"; to: 0; duration: Motion.contentOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
            NumberAnimation { target: shift; property: "y"; to: -8; duration: Motion.contentOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
        }
        ScriptAction {
            script: {
                shift.y = 10;
                root.settle();
            }
        }
        ParallelAnimation {
            NumberAnimation { target: page; property: "opacity"; to: 1; duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            NumberAnimation { target: shift; property: "y"; to: 0; duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }
    }
}
