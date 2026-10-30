import QtQuick
import qs.common
import qs.services

// A live activity's moment: the middle island grows a little (wider, a bit
// taller) to say one thing, then shrinks back into it. MorphCard, with the
// gentle curve the bar's own reveals use: it's a small change of size, not a
// panel opening.
//
//      ╭────────────────────────────────────────╮
//      │ (⚡) Charging  1h 20m to full   ▮▮▯ 36% │
//      ╰────────────────────────────────────────╯
//
// Click: the obvious thing (Activities.activate). Hover: it stays. Right
// click: away with it. The same kind again while it shows: the new content
// slides in, the card's width glides to fit.
Item {
    id: root

    // The moment to show (null = shrink back).
    property var entry: null
    property int revision: 0
    // Width of the middle island right now: where we start and end.
    property real startWidth: 200
    property bool open: false

    readonly property bool covering: morph.covering
    readonly property bool settled: morph.settled
    readonly property alias cardItem: morph.card
    readonly property bool revealed: morph.revealed

    // Stays on the last one while shrinking back.
    property var shown: null
    readonly property var v: Activities.view(shown)
    readonly property real pad: 8

    onEntryChanged: {
        if (!entry)
            return;
        if (!shown || !revealed)
            shown = entry;
        else
            swap.restart();
    }
    onRevisionChanged: {
        if (entry && shown && revealed)
            swap.restart();
        else if (entry)
            shown = entry;
    }
    onShownChanged: restartTimer()
    onRevealedChanged: restartTimer()

    function restartTimer() {
        timer.stop();
        remaining = 1;
        if (open && revealed && entry)
            timer.restart();
    }

    // New content for the same kind: out upward, in from below.
    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: content; property: "opacity"; to: 0; duration: Motion.contentOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
            NumberAnimation { target: shift; property: "y"; to: -8; duration: Motion.contentOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
        }
        ScriptAction {
            script: {
                root.shown = root.entry;
                shift.y = 8;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: content; property: "opacity"; to: 1; duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            NumberAnimation { target: shift; property: "y"; to: 0; duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }
    }

    property real remaining: 1
    NumberAnimation {
        id: timer
        target: root
        property: "remaining"
        from: 1
        to: 0
        duration: Math.max(500, Style.activityDuration)
        paused: running && hover.hovered
        onFinished: Activities.done()
    }

    // The card's width: what's in it, never narrower than the island. It
    // glides when the content changes while open (not while growing: the
    // morph carries it then).
    readonly property real wantWidth: Math.max(startWidth, Math.min(Style.activityMaxWidth, content.implicitWidth + pad * 2 + 8))
    property real cardWidth: wantWidth
    Behavior on cardWidth {
        enabled: root.revealed
        NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle }
    }

    MorphCard {
        id: morph

        anchors.fill: parent
        fromX: (width - root.startWidth) / 2
        fromY: Style.islandTop
        fromWidth: root.startWidth
        toWidth: root.cardWidth
        toHeight: Style.activityHeight
        radius: Style.activityHeight / 2
        glassOpacity: Style.notifOpacity
        curve: Motion.gentle
        // A short way to go: quick, so the empty pill on the way back is brief.
        durationIn: 400
        durationOut: 300
        open: root.open

        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: Activities.activate(root.shown)
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: Activities.done()
        }

        Row {
            id: content

            readonly property real room: Style.activityMaxWidth - root.pad * 2 - 8
            anchors.centerIn: parent
            spacing: 10
            transform: Translate {
                id: shift
            }

            // The picture (a screenshot, a copied picture), or a badge with
            // the icon (or the copied color).
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: picture.visible ? picture.width : 30
                height: 30

                RoundedTexture {
                    id: picture
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (root.v?.image ?? "") !== "" && pictureSource.status === Image.Ready
                    width: pictureSource.status === Image.Ready && pictureSource.implicitHeight > 0
                        ? Math.min(54, Math.max(30, 30 * pictureSource.implicitWidth / pictureSource.implicitHeight)) : 30
                    height: 30
                    radius: 8
                    source: pictureSource
                }
                Image {
                    id: pictureSource
                    visible: false
                    source: root.v?.image ?? ""
                    sourceSize: Qt.size(120, 68)
                    asynchronous: true
                    cache: false
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !picture.visible
                    radius: height / 2
                    color: (root.v?.swatch ?? "") !== "" ? root.v.swatch
                         : root.v?.badge === "primary" ? Colors.primary
                         : root.v?.badge === "tertiary" ? Colors.tertiaryContainer
                         : root.v?.badge === "plain" ? Style.alpha(Colors.textOnSurface, 0.1)
                         : Colors.secondaryContainer
                    border.width: (root.v?.swatch ?? "") !== "" ? 1 : 0
                    border.color: Style.alpha(Colors.textOnSurface, 0.25)

                    Icon {
                        anchors.centerIn: parent
                        visible: (root.v?.swatch ?? "") === ""
                        name: root.v?.icon ?? ""
                        size: 18
                        color: root.v?.badge === "primary" ? Colors.textOnPrimary
                             : root.v?.badge === "tertiary" ? Colors.textOnTertiaryContainer
                             : root.v?.badge === "plain" ? Colors.textOnSurface
                             : Colors.textOnSecondaryContainer
                    }
                }
            }

            StyledText {
                id: title
                anchors.verticalCenter: parent.verticalCenter
                text: root.v?.title ?? ""
                weight: 650
            }

            StyledText {
                id: detail
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                role: "label"
                weight: 500
                text: root.v?.detail ?? ""
                color: Colors.textOnSurfaceVariant
                elide: Text.ElideRight
                // What's left of the room once the rest is in.
                width: Math.min(implicitWidth, Math.max(40, content.room - 30 - title.implicitWidth - trailing.width - content.spacing * 3))
            }

            // The value: a level (a small battery for the charger) and a number.
            Row {
                id: trailing
                anchors.verticalCenter: parent.verticalCenter
                visible: (root.v?.value ?? "") !== ""
                width: visible ? implicitWidth : 0
                spacing: 6

                // A small battery: outline, cap, and the charge inside.
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (root.v?.gauge ?? -1) >= 0
                    width: 27
                    height: 13

                    Rectangle {
                        id: shell
                        width: 24
                        height: parent.height
                        radius: 4
                        color: "transparent"
                        border.width: 1.5
                        border.color: Style.alpha(Colors.textOnSurface, 0.45)
                    }
                    Rectangle {
                        x: shell.width + 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: 5
                        radius: 1
                        color: Style.alpha(Colors.textOnSurface, 0.45)
                    }
                    Rectangle {
                        x: 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(2, (shell.width - 6) * Math.max(0, Math.min(1, root.v?.gauge ?? 0)))
                        height: parent.height - 6
                        radius: 1.5
                        color: root.v?.badge === "primary" ? Colors.primary
                             : (root.v?.gauge ?? 1) <= Style.batteryLow / 100 ? Colors.error : Colors.textOnSurface
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "title"
                    text: root.v?.value ?? ""
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }
}
