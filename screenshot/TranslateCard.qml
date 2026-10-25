import QtQuick
import QtQuick.Effects
import qs.common
import "../services/translate.js" as Lang

// The screenshot overlay's translate card (screenshot/ShotView.qml puts it
// next to the pick): what was read, its translation, and the buttons.
//
//   ╭──────────────────────────────────────────────╮
//   │ 文A  To Vietnamese               ⇄   ⧉   ×   │
//   │ The quick brown fox jumps over the lazy dog.  │
//   │ ───────────────────────────────────────────── │
//   │ Con cáo nâu nhanh nhẹn nhảy qua con chó lười. │
//   │ Vietnamese text needs tesseract-data-vie       │
//   ╰──────────────────────────────────────────────╯
//
// ⇄ translates the other way (the pair's other language), ⧉ copies the
// translation, × closes (so do Esc and a click outside, ShotView's).
// The glass is frosted from the frozen screen under it (`backdrop`): the
// overlay is opaque, so mango has nothing to blur.
// Plain QtQuick, previewable offscreen like ShotView.
Item {
    id: root

    property Item backdrop: null        // the frozen screen (ShotView's)
    property string stage: ""           // reading | translating | done | empty | failed
    property string original: ""
    property string translation: ""
    property string from: ""
    property string to: ""
    property string error: ""
    property string note: ""
    property real maxHeight: 520

    signal swap()
    signal copy()
    signal retry()
    signal close()

    readonly property bool working: stage === "reading" || stage === "translating"
    readonly property bool canCopy: stage === "done" && translation !== ""
    readonly property bool canSwap: original !== "" && stage !== "reading"

    // A tap on Copy: its icon is a tick for a moment.
    property bool copied: false
    Timer {
        id: copiedTimer
        interval: 1400
        onTriggered: root.copied = false
    }
    function copyNow() {
        if (!canCopy)
            return;
        copied = true;
        copiedTimer.restart();
        copy();
    }
    onTranslationChanged: copied = false

    implicitHeight: Math.min(maxHeight, content.implicitHeight + 32)

    // In: a little rise and fade.
    opacity: 0
    scale: 0.97
    Component.onCompleted: {
        opacity = 1;
        scale = 1;
    }
    Behavior on opacity { NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
    Behavior on scale { NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
    Behavior on implicitHeight { NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

    // Clicks on the card stay on it (a click outside closes).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    // ---- The glass ---------------------------------------------------------------------------
    // The frozen screen under the card, blurred, cut to its corners.
    readonly property real spill: 40
    ShaderEffectSource {
        id: piece
        sourceItem: root.backdrop
        sourceRect: Qt.rect(root.x - root.spill, root.y - root.spill, root.width + 2 * root.spill, root.height + 2 * root.spill)
        textureSize: Qt.size(Math.max(1, Math.ceil((root.width + 2 * root.spill) / 2)), Math.max(1, Math.ceil((root.height + 2 * root.spill) / 2)))
        visible: false
        live: true
    }
    Item {
        anchors.fill: parent
        visible: root.backdrop !== null
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: shape
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        MultiEffect {
            x: -root.spill
            y: -root.spill
            width: root.width + 2 * root.spill
            height: root.height + 2 * root.spill
            source: piece
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 48
            blur: 1
            saturation: 0.15
            brightness: -0.04
        }
    }
    Item {
        id: shape
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: glass.radius
        }
    }
    Glass {
        id: glass
        anchors.fill: parent
        radius: 22
        color: Style.alpha(Colors.surfaceContainer, 0.78)
    }

    // ---- What's in it -----------------------------------------------------------------------
    component CardButton: MouseArea {
        id: button
        property string icon: ""
        property bool on: true
        width: 36
        height: 36
        hoverEnabled: true
        enabled: on
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colors.textOnSurface
            opacity: button.containsMouse ? (button.pressed ? Style.pressTint : Style.hoverTint) : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Icon {
            anchors.centerIn: parent
            name: button.icon
            size: 19
            fill: 0
            opacity: button.on ? 1 : 0.35
        }
    }

    component Spinner: Icon {
        name: "progress_activity"
        size: 18
        color: Colors.textOnSurfaceVariant
        RotationAnimation on rotation {
            running: true
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
        }
    }

    Column {
        id: content
        x: 16
        y: 12
        width: root.width - 32
        spacing: 8

        // Which way, and the buttons.
        Item {
            width: parent.width
            height: 36

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "translate"
                    size: 18
                    color: Colors.primary
                }
                StyledText {
                    id: direction
                    anchors.verticalCenter: parent.verticalCenter
                    role: "label"
                    color: Colors.textOnSurfaceVariant
                    // "Vietnamese → English", or "To Vietnamese" when the
                    // language it's in is Google's to tell.
                    text: root.stage === "reading" || root.stage === "empty" ? "Translate"
                          : root.from !== "" ? Lang.languageName(root.from) + "  →  " + Lang.languageName(root.to)
                          : "To " + Lang.languageName(root.to)
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: -6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                CardButton {
                    objectName: "swapButton"
                    icon: "swap_horiz"
                    on: root.canSwap
                    onClicked: root.swap()
                }
                CardButton {
                    objectName: "copyButton"
                    icon: root.copied ? "check" : "content_copy"
                    on: root.canCopy
                    onClicked: root.copyNow()
                }
                CardButton {
                    objectName: "closeButton"
                    icon: "close"
                    onClicked: root.close()
                }
            }
        }

        // What was read (a few lines of it).
        StyledText {
            visible: root.original !== ""
            width: parent.width
            text: root.original
            role: "caption"
            color: Colors.textOnSurfaceVariant
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
        }

        Rectangle {
            visible: root.original !== ""
            width: parent.width
            height: 1
            color: Style.alpha(Colors.textOnSurface, 0.12)
        }

        // The translation (scrolls when long), or where it's at.
        Flickable {
            id: scroller
            visible: root.stage === "done"
            width: parent.width
            height: Math.min(contentHeight, root.maxHeight - 140)
            contentHeight: translated.implicitHeight
            clip: contentHeight > height
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            StyledText {
                id: translated
                width: scroller.width
                text: root.translation
                role: "title"
                weight: 500
                wrapMode: Text.Wrap
                lineHeight: 1.12
            }
        }

        Row {
            visible: root.working
            spacing: 8
            height: 28
            Spinner {
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.stage === "reading" ? "Reading the text…" : "Translating…"
                role: "body"
                color: Colors.textOnSurfaceVariant
            }
        }

        StyledText {
            visible: root.stage === "empty"
            width: parent.width
            text: "No text found here"
            role: "body"
            color: Colors.textOnSurfaceVariant
            wrapMode: Text.Wrap
        }

        // Failed: why, and Try again.
        Row {
            visible: root.stage === "failed"
            width: parent.width
            spacing: 10
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - retryButton.width - 10
                text: root.error !== "" ? root.error : "Couldn't translate it"
                role: "body"
                color: Colors.error
                wrapMode: Text.Wrap
            }
            MouseArea {
                id: retryButton
                objectName: "retryButton"
                anchors.verticalCenter: parent.verticalCenter
                width: retryText.implicitWidth + 28
                height: 36
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.retry()

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Style.alpha(Colors.textOnSurface, retryButton.containsMouse ? 0.16 : 0.1)
                }
                StyledText {
                    id: retryText
                    anchors.centerIn: parent
                    text: "Try again"
                    weight: 600
                }
            }
        }

        StyledText {
            visible: root.note !== ""
            width: parent.width
            text: root.note
            role: "micro"
            color: Colors.textOnSurfaceVariant
            opacity: 0.85
            wrapMode: Text.Wrap
        }
    }
}
