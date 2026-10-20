import QtQuick
import qs.common
import qs.services

// Privacy dots, like a Mac's: orange while an app records the microphone,
// green while the camera is on, purple while the screen is shared (by
// another app: the shell's own recording has its red dot). On the bar only
// while one of them is lit. Hover: which apps. Click the orange one: mute
// the microphone (click again: unmute); it's a ring while muted.
Reveal {
    id: root

    // (`wanted`: the bar's slot reads it, see BarContent.)
    readonly property bool wanted: shown || implicitWidth > 0.5
    // The apps' names show while the mouse is over the dots.
    property bool showNames: hover.hovered

    anchors.verticalCenter: parent?.verticalCenter
    shown: Privacy.micOn || Privacy.cameraOn || Privacy.sharing

    // The camera is only looked at while a privacy item is on the bar.
    Component.onCompleted: Privacy.use(1)
    Component.onDestruction: Privacy.use(-1)

    Row {
        HoverHandler {
            id: hover
        }

        Dot {
            lit: Privacy.micOn
            color: Style.privacyMicColor
            ring: Privacy.micMuted
            apps: Privacy.micApps
            note: Privacy.micMuted ? "muted" : ""
            clickable: true
            showNames: root.showNames
            onClicked: Privacy.toggleMute()
        }
        Dot {
            lit: Privacy.cameraOn
            color: Style.privacyCameraColor
            apps: Privacy.cameraApps
            showNames: root.showNames
        }
        Dot {
            lit: Privacy.sharing
            color: Style.privacyShareColor
            apps: Privacy.shareApps
            showNames: root.showNames
        }
    }

    // One dot, and the apps' names next to it while hovered (each slides on
    // its own, so the names don't wait for the dot to settle).
    component Dot: Row {
        id: dot

        property bool lit: false
        property color color: "white"
        property bool ring: false
        property var apps: []
        property string note: ""
        property bool clickable: false
        property bool showNames: false
        signal clicked

        anchors.verticalCenter: parent?.verticalCenter

        Reveal {
            anchors.verticalCenter: parent.verticalCenter
            shown: dot.lit

            Clickable {
                implicitHeight: 18
                padding: 5
                cursorShape: dot.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (dot.clickable) dot.clicked()

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: dot.ring ? "transparent" : dot.color
                    border.width: dot.ring ? 1.5 : 0
                    border.color: dot.color

                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }
        }

        Reveal {
            anchors.verticalCenter: parent.verticalCenter
            shown: dot.lit && dot.showNames && names.text !== ""

            Item {
                implicitWidth: Math.min(names.implicitWidth, Style.privacyNamesWidth) + 6
                implicitHeight: names.implicitHeight

                StyledText {
                    id: names
                    width: parent.width - 6
                    text: dot.apps.join(", ") + (dot.note !== "" ? (dot.apps.length > 0 ? " · " : "") + dot.note : "")
                    role: "caption"
                    elide: Text.ElideRight
                }
            }
        }
    }
}
