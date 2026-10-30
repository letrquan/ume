import QtQuick
import Quickshell
import qs.common
import qs.services

// The updates panel's card. It grows out of the bar's updates item (like
// the volume popup), sits right under it and shrinks back when it closes.
//
//      ╭───────────────────────────────────────╮
//      │ Updates                            ⟳  │
//      │ 73 waiting · checked 12 min ago       │
//      │ ⚠ Look first: linux-cachyos-rc, mesa… │   heads-up (Updates.headsUp)
//      │ 📰 Arch news newer than your last …    │   click: the page
//      │ › Repo 68                             │   each list folds
//      │ › AUR 2              Build in terminal│   paru -Sua, in a terminal
//      │ › Flatpak 3                           │
//      │               In terminal  ( Update ) │
//      ╰───────────────────────────────────────╯
//
// Update installs the repo packages and the Flatpaks right here
// (services/UpdateRun.qml): "Installing 12 of 68 · mesa", a bar, the step,
// Details (the output's last lines). Closing the panel doesn't stop it.
// Update checks again first when the list is older than 10 minutes. With
// heads-up packages among the updates, it then asks again, listing them:
// they can undo what was set up by hand (the kernel, the
// firmware links of the audio fix). There's no "all but those": that's a
// partial upgrade, which Arch doesn't support.
// When it's done: what it did, restart hints, the .pacnew files pacman
// left; failures with the error and "Finish in terminal".
// Plain QtQuick + services, so it can be previewed.
Item {
    id: root

    // The item it grows out of, in this item's (the screen's) coordinates;
    // empty: the top right corner (opened over IPC without the item).
    property rect from: Qt.rect(0, 0, 0, 0)
    property bool open: false

    signal closeRequested()

    // Back in the item and hidden: the window can go now.
    readonly property bool settled: !open && t === 0

    function focusKeys() {
        keys.forceActiveFocus();
    }

    // ---- What it shows ---------------------------------------------------------------
    // list | confirm | running | result
    readonly property string mode: UpdatesState.confirming ? "confirm"
        : UpdateRun.busy ? "running"
        : UpdateRun.stage === "done" && UpdateRun.result !== "cancelled" ? "result"
        : "list"

    readonly property bool installable: Updates.repo.length > 0 || (Style.updatesFlatpak && Updates.flatpak.length > 0)
    // On battery: a warning below 30 %, no Update below 15 %.
    readonly property bool onBattery: BatteryCare.hasBattery && BatteryCare.unplugged
    readonly property bool batteryLow: onBattery && BatteryCare.percent < 30
    readonly property bool batteryBlocks: onBattery && BatteryCare.percent < 15
    readonly property bool canUpdate: installable && !Updates.updating && !UpdateRun.busy && !batteryBlocks
        && !UpdatesState.freshening

    // ---- What the buttons do (tests call these too) -------------------------------------
    // (A list older than 10 minutes is checked again first: UpdatesState.)
    function update() {
        if (canUpdate)
            UpdatesState.update();
    }
    function confirm() {
        UpdatesState.confirming = false;
        if (canUpdate)
            UpdateRun.start();
    }
    function back() {
        UpdatesState.confirming = false;
    }
    function inTerminal() {
        if (UpdateRun.busy || Updates.updating)
            return;
        Updates.run();
        root.closeRequested();
    }
    function finishInTerminal() {
        UpdateRun.dismiss();
        if (!Updates.updating)
            Updates.run();
        root.closeRequested();
    }
    function buildAur() {
        if (Updates.updating || UpdateRun.busy)
            return;
        Updates.buildAur();
        root.closeRequested();
    }
    function checkNow() {
        Updates.check("panel");
    }
    function finish() {
        UpdateRun.dismiss();
    }
    function restartShell() {
        UpdateRun.restartShell();
        root.closeRequested();
    }

    // "checked 12 min ago" stays true while it's open.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        enabled: root.open
    }

    // ---- Where the card goes ----------------------------------------------------------------
    readonly property rect origin: from.width > 0 ? from
        : Qt.rect(width - Style.islandSide - 40, Style.islandTop + (Style.islandHeight - Style.itemHeight) / 2, 32, Style.itemHeight)
    readonly property real toWidth: Style.updatesPanelWidth
    readonly property real toX: Math.max(Style.marginEdge,
        Math.min(width - toWidth - Style.marginEdge, origin.x + origin.width / 2 - toWidth / 2))
    readonly property real toY: Style.barBottom + Style.osdGap
    readonly property int pad: 14
    readonly property int gap: 10
    // Never past the screen (the dock's room kept): the lists scroll.
    readonly property real maxHeight: Math.max(260, height - toY - 72)
    readonly property real fixedHeight: header.height + footer.height + 2 * gap + 2 * pad
    readonly property real bodyRoom: maxHeight - fixedHeight
    readonly property real bodyHeight: Math.min(body.implicitHeight, bodyRoom)
    // The card's height eases on its own, so lists folding glide.
    property real toHeight: fixedHeight + bodyHeight
    Behavior on toHeight {
        NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
    }

    // 0 = the item, 1 = the card.
    property real t: 0
    onOpenChanged: {
        morph.stop();
        morph.to = open ? 1 : 0;
        morph.duration = open ? Motion.morphIn : Motion.morphOut;
        morph.start();
    }
    NumberAnimation {
        id: morph
        target: root
        property: "t"
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasized
    }

    function lerp(a, b) {
        return a + (b - a) * t;
    }

    // A click on the card itself must not reach the window's "outside" catcher.
    MouseArea {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        acceptedButtons: Qt.AllButtons
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: {
            if (UpdatesState.confirming)
                root.back();
            else
                root.closeRequested();
        }
    }

    Item {
        id: card

        x: root.lerp(root.origin.x, root.toX)
        y: root.lerp(root.origin.y, root.toY)
        width: root.lerp(root.origin.width, root.toWidth)
        height: root.lerp(root.origin.height, root.toHeight)
        // Fades in over the first bit, so it doesn't start as a solid pill
        // over the item.
        opacity: Math.min(1, root.t * 5)
        visible: root.t > 0

        Glass {
            anchors.fill: parent
            radius: root.lerp(root.origin.height / 2, Style.radiusPopup)
            color: Style.alpha(Colors.surfaceContainer, root.lerp(Style.islandOpacity, Style.ccOpacity))
        }

        // The content: clipped to the card, slides in near the end of the
        // opening and leaves first when closing (like the volume popup).
        Item {
            id: inner
            anchors.fill: parent
            clip: true
            readonly property bool revealed: root.open && root.t > 0.6
            opacity: revealed ? 1 : 0
            transform: Translate {
                y: inner.revealed ? 0 : 6
                Behavior on y {
                    NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: inner.revealed ? Motion.contentIn : Motion.contentOut
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: inner.revealed ? Motion.emphasizedDecel : Motion.emphasizedAccel
                }
            }

            // ---- Updates                                         ⟳ ----
            Item {
                id: header
                x: root.pad
                y: root.pad
                width: root.toWidth - 2 * root.pad
                height: 40

                Column {
                    anchors.left: parent.left
                    anchors.right: checkButton.left
                    anchors.leftMargin: 4
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    StyledText {
                        width: parent.width
                        text: root.mode === "confirm" ? "Before you update"
                            : root.mode === "running" ? "Installing updates"
                            : "Updates"
                        role: "title"
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        text: {
                            clock.date;
                            if (root.mode === "running")
                                return "Keep the lid open: closing it still suspends";
                            if (root.mode === "result")
                                return (UpdateRun.run.finished ?? 0) > 0
                                    ? "Finished " + Qt.formatTime(new Date(UpdateRun.run.finished * 1000), "HH:mm")
                                    : "It didn't finish";
                            if (root.mode === "confirm")
                                return Updates.summary;
                            if (UpdatesState.freshening)
                                return "Checking again before updating…";
                            if (Updates.checking)
                                return "Checking…";
                            if (Updates.failed !== "")
                                return Updates.failed;
                            return (Updates.count === 0 ? "Up to date" : Updates.count + " waiting")
                                + " · checked " + Updates.ago(Updates.checkedAt);
                        }
                        role: "caption"
                        color: Colors.textOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                // Check now (spins while it checks).
                RoundButton {
                    id: checkButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.mode === "list"
                    icon: "refresh"
                    enabled: !Updates.checking
                    spinning: Updates.checking
                    onClicked: root.checkNow()
                }
            }

            // ---- The lists, the progress or what it did (scrolls when long) ----
            Flickable {
                id: scroller
                x: root.pad
                y: header.y + header.height + root.gap
                width: root.toWidth - 2 * root.pad
                height: root.bodyHeight
                contentHeight: body.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                interactive: contentHeight > height

                Column {
                    id: body
                    width: scroller.width
                    spacing: 8

                    // ---- list ----------------------------------------------------------
                    Note {
                        visible: root.mode === "list" && UpdateRun.result === "cancelled"
                        icon: "block"
                        text: "Cancelled: the password wasn't given, nothing was changed"
                    }
                    Note {
                        visible: root.mode === "list" && UpdateRun.refused !== ""
                        icon: "lock"
                        tone: "warn"
                        text: UpdateRun.refused
                    }
                    Note {
                        visible: root.mode === "list" && Updates.updating
                        icon: "terminal"
                        text: "The update is open in a terminal"
                    }
                    Note {
                        visible: root.mode === "list" && Updates.headsUp.length > 0
                        icon: "warning"
                        tone: "accent"
                        text: "Look first: " + Updates.headsUp.slice(0, 8).join(", ")
                            + (Updates.headsUp.length > 8 ? " +" + (Updates.headsUp.length - 8) : "")
                    }
                    Note {
                        visible: root.mode === "list" && root.batteryLow && root.installable
                        icon: "battery_alert"
                        tone: "warn"
                        text: root.batteryBlocks ? "On battery at " + BatteryCare.percent + " %: plug in to update"
                            : "On battery at " + BatteryCare.percent + " %: better plugged in"
                    }

                    // Arch news newer than the last full upgrade.
                    SectionLabel {
                        visible: root.mode === "list" && ArchNews.fresh.length > 0
                        text: "Arch news since your last upgrade"
                    }
                    Repeater {
                        model: root.mode === "list" ? ArchNews.fresh : []

                        NewsRow {
                            required property var modelData
                            width: body.width
                            item: modelData
                        }
                    }

                    Group {
                        kind: "repo"
                        title: "Repo"
                        items: root.mode === "list" ? Updates.repo : []
                    }
                    Group {
                        kind: "aur"
                        title: "AUR"
                        items: root.mode === "list" ? Updates.aur : []
                        action: "Build in terminal"
                        actionEnabled: !Updates.updating && !UpdateRun.busy
                        onAct: root.buildAur()
                    }
                    Group {
                        kind: "flatpak"
                        title: "Flatpak"
                        items: root.mode === "list" ? Updates.flatpak : []
                    }

                    Item {
                        visible: root.mode === "list" && Updates.count === 0
                        width: body.width
                        height: 64

                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                name: "check_circle"
                                size: 26
                                color: Colors.textOnSurfaceVariant
                            }
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Updates.checking ? "Checking…" : "Everything is up to date"
                                color: Colors.textOnSurfaceVariant
                            }
                        }
                    }

                    // ---- confirm -------------------------------------------------------
                    Note {
                        visible: root.mode === "confirm"
                        icon: "warning"
                        tone: "accent"
                        text: "These can affect things set up by hand:"
                    }
                    Flow {
                        visible: root.mode === "confirm"
                        width: body.width
                        spacing: 6

                        Repeater {
                            model: root.mode === "confirm" ? Updates.headsUp : []

                            Rectangle {
                                required property var modelData
                                width: chip.implicitWidth + 18
                                height: 26
                                radius: 13
                                color: Style.alpha(Colors.primary, 0.16)

                                StyledText {
                                    id: chip
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    role: "label"
                                    color: Colors.primary
                                }
                            }
                        }
                    }
                    StyledText {
                        visible: root.mode === "confirm"
                        width: body.width
                        leftPadding: 4
                        rightPadding: 4
                        text: "Everything is updated together: leaving some out is a partial upgrade, which Arch doesn't support. "
                            + "Check what you set up by hand once it's done."
                        role: "caption"
                        color: Colors.textOnSurfaceVariant
                        wrapMode: Text.Wrap
                    }

                    // ---- running -------------------------------------------------------
                    StyledText {
                        visible: root.mode === "running"
                        width: body.width
                        leftPadding: 4
                        text: UpdateRun.progressText
                        elide: Text.ElideRight
                    }
                    ProgressBar {
                        visible: root.mode === "running"
                        width: body.width
                        value: UpdateRun.fraction
                    }

                    // ---- result --------------------------------------------------------
                    Item {
                        visible: root.mode === "result"
                        width: body.width
                        height: resultText.implicitHeight + 8

                        Icon {
                            id: resultIcon
                            x: 4
                            y: 4
                            name: UpdateRun.result === "ok" ? "check_circle"
                                : UpdateRun.result === "needsYou" ? "front_hand" : "error"
                            size: 26
                            color: UpdateRun.result === "ok" ? Colors.primary : Colors.error
                        }
                        Column {
                            id: resultText
                            anchors.left: resultIcon.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            y: 4
                            spacing: 2

                            StyledText {
                                width: parent.width
                                text: UpdateRun.summary
                                role: "title"
                                wrapMode: Text.Wrap
                            }
                            StyledText {
                                width: parent.width
                                visible: text !== ""
                                text: {
                                    switch (UpdateRun.result) {
                                    case "ok":
                                        return UpdateRun.restartFor.length > 0 || UpdateRun.shellFor.length > 0
                                            ? "" : "Everything went through";
                                    case "needsYou":
                                        return (UpdateRun.question || "pacman asked a question")
                                            + "\nWith no one to answer, it said no and stopped: nothing was changed.";
                                    case "stopped":
                                        return "It ended before finishing. Finish in the terminal, so nothing stays half done.";
                                    }
                                    // A file in the way ("alsa-ucm-conf: /usr/share/… exists in
                                    // filesystem"): a hand-placed file the package now ships.
                                    return (UpdateRun.errorLine || "See Details")
                                        + (UpdateRun.clash !== "" ? "\n" + UpdateRun.clash : "");
                                }
                                role: "caption"
                                color: Colors.textOnSurfaceVariant
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                    Note {
                        visible: root.mode === "result" && UpdateRun.restartFor.length > 0
                        icon: "restart_alt"
                        tone: UpdateRun.modulesGone ? "warn" : "accent"
                        text: (UpdateRun.modulesGone
                                ? "Restart soon: the running kernel's modules were replaced, so drivers that aren't loaded yet (a USB device, sound after sleep) won't load until you do. "
                                : "Restart to finish: ")
                            + UpdateRun.restartFor.slice(0, 6).join(", ")
                            + (UpdateRun.restartFor.length > 6 ? " +" + (UpdateRun.restartFor.length - 6) : "")
                    }
                    Note {
                        visible: root.mode === "result" && UpdateRun.shellFor.length > 0
                        icon: "refresh"
                        text: "The shell still runs the old " + (UpdateRun.shellFor.some(n => /^quickshell/.test(n)) ? "Quickshell" : "Qt")
                        button: "Restart the shell"
                        onPressed: root.restartShell()
                    }
                    SectionLabel {
                        visible: root.mode === "result" && UpdateRun.pacnew.length > 0
                        text: "New config files (.pacnew): merge with pacdiff"
                    }
                    Repeater {
                        model: root.mode === "result" ? UpdateRun.pacnew : []

                        Text {
                            required property var modelData
                            width: body.width
                            leftPadding: 6
                            text: modelData
                            textFormat: Text.PlainText
                            font.family: "monospace"
                            font.pixelSize: Style.textSize("caption")
                            color: Colors.textOnSurface
                            elide: Text.ElideMiddle
                            renderType: Text.NativeRendering
                        }
                    }

                    // ---- Details (running and result) ----------------------------------
                    Row {
                        id: detailsRow
                        visible: (root.mode === "running" || root.mode === "result") && UpdateRun.lines.length > 0
                        spacing: 0

                        TextButton {
                            text: UpdatesState.showLog ? "Hide details" : "Details"
                            icon: UpdatesState.showLog ? "expand_less" : "expand_more"
                            onClicked: UpdatesState.showLog = !UpdatesState.showLog
                        }
                    }
                    LogBox {
                        visible: detailsRow.visible && UpdatesState.showLog
                        width: body.width
                    }
                }
            }

            // ---- The buttons ----------------------------------------------------------------
            Row {
                id: footer
                anchors.right: parent.right
                anchors.rightMargin: root.pad
                y: scroller.y + scroller.height + root.gap
                height: 34
                spacing: 8
                layoutDirection: Qt.LeftToRight

                PillButton {
                    visible: root.mode === "confirm"
                    text: "Back"
                    onClicked: root.back()
                }
                PillButton {
                    visible: root.mode === "confirm"
                    text: "Update anyway"
                    filled: true
                    enabled: root.canUpdate
                    onClicked: root.confirm()
                }

                PillButton {
                    visible: root.mode === "result" && UpdateRun.result !== "ok"
                    text: "Done"
                    onClicked: root.finish()
                }
                PillButton {
                    visible: root.mode === "result" && UpdateRun.result !== "ok"
                    text: "Finish in terminal"
                    filled: true
                    onClicked: root.finishInTerminal()
                }

                PillButton {
                    visible: root.mode === "list" || root.mode === "running" || (root.mode === "result" && UpdateRun.result === "ok")
                    text: "In terminal"
                    enabled: root.mode !== "running" && !Updates.updating
                    onClicked: root.inTerminal()
                }
                PillButton {
                    visible: root.mode === "list"
                    text: "Update"
                    filled: true
                    enabled: root.canUpdate
                    onClicked: root.update()
                }
                PillButton {
                    visible: root.mode === "result" && UpdateRun.result === "ok"
                    text: "Done"
                    filled: true
                    onClicked: root.finish()
                }
            }
        }
    }

    // ---- Small parts --------------------------------------------------------------------------
    // A small grey section title, like macOS menus.
    component SectionLabel: StyledText {
        leftPadding: 6
        topPadding: 4
        role: "label"
        color: Colors.textOnSurfaceVariant
    }

    // A tinted line with an icon: plain, accent (look first) or warn.
    component Note: Rectangle {
        id: note
        property string icon: ""
        property string text: ""
        property string tone: "plain"
        property string button: ""
        signal pressed()

        width: parent?.width ?? 0
        height: noteRow.implicitHeight + 16
        radius: 12
        color: tone === "warn" ? Style.alpha(Colors.error, 0.16)
             : tone === "accent" ? Style.alpha(Colors.primary, 0.14)
             : Style.alpha(Colors.textOnSurface, 0.06)

        Row {
            id: noteRow
            x: 10
            y: 8
            width: parent.width - 20
            spacing: 8

            Icon {
                id: noteIcon
                name: note.icon
                size: 18
                color: note.tone === "warn" ? Colors.error : note.tone === "accent" ? Colors.primary : Colors.textOnSurfaceVariant
            }
            Column {
                width: noteRow.width - noteIcon.width - noteRow.spacing
                spacing: 6

                StyledText {
                    width: parent.width
                    text: note.text
                    role: "label"
                    weight: 550
                    wrapMode: Text.Wrap
                }
                PillButton {
                    visible: note.button !== ""
                    text: note.button
                    small: true
                    onClicked: note.pressed()
                }
            }
        }
    }

    // One package list: › Repo 68, folds open and shut; rows are
    // name   from → to.
    component Group: Column {
        id: group
        property string kind: ""
        property string title: ""
        property var items: []
        property string action: ""
        property bool actionEnabled: true
        signal act()
        readonly property bool unfolded: UpdatesState.expanded[kind] ?? items.length <= 6

        visible: items.length > 0
        width: parent?.width ?? 0

        MouseArea {
            id: groupHeader
            width: parent.width
            height: 30
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: UpdatesState.setExpanded(group.kind, !group.unfolded)

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Colors.textOnSurface
                opacity: groupHeader.pressed ? Style.pressTint : groupHeader.containsMouse ? Style.hoverTint : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }
            Icon {
                id: chevron
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron_right"
                size: 18
                color: Colors.textOnSurfaceVariant
                rotation: group.unfolded ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
            }
            StyledText {
                id: groupTitle
                anchors.left: chevron.right
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: group.title
                role: "label"
            }
            StyledText {
                anchors.left: groupTitle.right
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: String(group.items.length)
                role: "caption"
                font.features: ({ "tnum": 1 })
                color: Colors.textOnSurfaceVariant
            }
            TextButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: group.action !== ""
                enabled: group.actionEnabled
                text: group.action
                icon: "terminal"
                onClicked: group.act()
            }
        }

        Repeater {
            model: group.unfolded ? group.items : []

            Item {
                id: pkg
                required property var modelData
                width: group.width
                height: 22

                StyledText {
                    x: 28
                    width: Math.max(60, parent.width - x - version.width - 12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: pkg.modelData.name
                    role: "caption"
                    weight: 600
                    elide: Text.ElideRight
                }
                StyledText {
                    id: version
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, group.width * 0.55)
                    horizontalAlignment: Text.AlignRight
                    text: pkg.modelData.from ? pkg.modelData.from + " → " + pkg.modelData.to
                        : pkg.modelData.to || pkg.modelData.branch || ""
                    role: "caption"
                    font.features: ({ "tnum": 1 })
                    color: Colors.textOnSurfaceVariant
                    elide: Text.ElideLeft
                }
            }
        }
    }

    // An Arch news item: its title and date; click opens it.
    component NewsRow: MouseArea {
        id: news
        property var item: ({})
        height: newsText.implicitHeight + 12
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ArchNews.open(news.item)

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Colors.textOnSurface
            opacity: news.pressed ? Style.pressTint : news.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Icon {
            id: newsIcon
            x: 6
            y: 6
            name: "newspaper"
            size: 18
            color: Colors.primary
        }
        Column {
            id: newsText
            anchors.left: newsIcon.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 6
            y: 6
            spacing: 1

            StyledText {
                width: parent.width
                text: news.item.title ?? ""
                role: "label"
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            StyledText {
                text: ArchNews.day(news.item.date ?? 0) + " · archlinux.org"
                role: "caption"
                color: Colors.textOnSurfaceVariant
            }
        }
    }

    // How far it is: a slim bar; while it can't tell (value < 0), a piece
    // sliding across.
    component ProgressBar: Rectangle {
        id: bar
        property real value: 0
        height: 6
        radius: 3
        clip: true
        color: Style.alpha(Colors.textOnSurface, 0.12)

        Rectangle {
            visible: bar.value >= 0
            height: parent.height
            radius: parent.radius
            width: Math.max(parent.height, parent.width * Math.max(0, bar.value))
            color: Colors.primary
            Behavior on width { NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        }
        Rectangle {
            id: sliding
            visible: bar.value < 0
            height: parent.height
            radius: parent.radius
            width: parent.width * 0.3
            color: Colors.primary
            NumberAnimation on x {
                running: sliding.visible && root.open
                loops: Animation.Infinite
                from: -bar.width * 0.3
                to: bar.width
                duration: 1300
                easing.type: Easing.InOutSine
            }
        }
    }

    // The output's last lines, monospace; follows the end unless you
    // scrolled up.
    component LogBox: Rectangle {
        id: box
        height: Math.min(200, logText.implicitHeight + 16)
        radius: 10
        color: Style.alpha(Colors.surfaceContainerLowest, 0.55)

        Flickable {
            id: logFlick
            anchors.fill: parent
            anchors.margins: 8
            contentHeight: logText.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            property bool atEnd: true
            onMovementEnded: atEnd = contentY >= contentHeight - height - 4
            onContentHeightChanged: if (atEnd) contentY = Math.max(0, contentHeight - height)
            onHeightChanged: if (atEnd) contentY = Math.max(0, contentHeight - height)

            Text {
                id: logText
                width: logFlick.width
                text: UpdateRun.lines.join("\n")
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                font.family: "monospace"
                font.pixelSize: Style.textSize("micro")
                color: Colors.textOnSurfaceVariant
                renderType: Text.NativeRendering
            }
        }
    }

    // A pill button: the main one filled (like the Tailscale page's).
    component PillButton: MouseArea {
        id: button
        property string text: ""
        property bool filled: false
        property bool small: false

        width: label.implicitWidth + (small ? 22 : 32)
        height: small ? 26 : 32
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        opacity: enabled ? 1 : 0.4

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: button.filled ? Colors.primary : Style.alpha(Colors.textOnSurface, 0.08)
            scale: button.pressed ? 0.94 : 1
            Behavior on scale {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: button.filled ? Colors.textOnPrimary : Colors.textOnSurface
                opacity: button.pressed ? Style.pressTint : button.containsMouse ? Style.hoverTint : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }
        }
        StyledText {
            id: label
            anchors.centerIn: parent
            text: button.text
            role: "label"
            weight: button.filled ? 700 : 600
            color: button.filled ? Colors.textOnPrimary : Colors.textOnSurface
        }
    }

    // Accent text with an icon: "Build in terminal", "Details".
    component TextButton: MouseArea {
        id: tb
        property string text: ""
        property string icon: ""

        width: tbRow.implicitWidth + 16
        height: 26
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        opacity: enabled ? 1 : 0.4

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Colors.primary
            opacity: tb.pressed ? Style.pressTint : tb.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Row {
            id: tbRow
            anchors.centerIn: parent
            spacing: 3

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: tb.icon !== ""
                name: tb.icon
                size: 15
                color: Colors.primary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: tb.text
                role: "label"
                color: Colors.primary
            }
        }
    }

    // A round icon button (check now); it can spin.
    component RoundButton: MouseArea {
        id: rb
        property string icon: ""
        property bool spinning: false

        width: 32
        height: 32
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colors.textOnSurface
            opacity: rb.pressed ? Style.pressTint : rb.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Icon {
            id: rbIcon
            anchors.centerIn: parent
            name: rb.icon
            size: 18
            color: Colors.textOnSurfaceVariant
            RotationAnimation on rotation {
                running: rb.spinning
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
                onRunningChanged: if (!running) rbIcon.rotation = 0
            }
        }
    }
}
