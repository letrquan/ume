import QtQuick
import QtQuick.Effects
import qs.common

// The "Panel" lock screen (Settings → Lock screen → Style), in the shell's
// own language: the wallpaper's colors (Colors), the islands' glass, Google
// Sans Flex, Material symbols and the M3 Expressive curves (Motion).
//
//   ╭ 🔒 Locked  since 06:31 ╮                            ╭ 🔋 84%  ⏻ ╮
//
//        ╭─────────────────────────────────────────────────────────╮
//        │ weather   │               12:34               │ system  │
//        │ fetch     │         Thursday, 15 October      │         │
//        │           │      ✈ Telegram 5 · m Messenger 2 │         │
//        │ playing   │      (you)  [ • • •         → ]   │ month   │
//        ╰─────────────────────────────────────────────────────────╯
//
// Opening (Caelestia's lock): a small rounded square with a lock spins in,
// the lock turns away and the square opens into the panel; then the
// islands drop in like the bar's. Unlocking plays it backwards. Behind: the blurred
// wallpaper. Which cards show: Style.lockShow*.
//
// lock.qml feeds it the password state; the cards read the shell's
// services themselves (Weather, SysStats, Mpris, UPower).
Item {
    id: root

    property string userName: "user"
    property string avatar: ""              // a picture, e.g. ~/.face
    property string authState: "idle"       // idle | busy | failed | success
    property string authMessage: ""
    property alias password: field.text
    property alias powerOpen: powerIsland.open
    property date lockedAt: new Date()
    property date now: new Date()

    // shown → the opening; leaving → the unlock animation.
    property bool shown: false
    readonly property bool leaving: authState === "success"
    readonly property real presence: shown && !leaving ? 1 : 0

    signal submit()
    signal power(string name)

    // ---- Sizes --------------------------------------------------------------------
    // The full panel is Caelestia's: 70 % of the screen height at 16:9. A side
    // with no cards (Settings → Lock screen) leaves the panel narrower.
    readonly property real gap: 24
    readonly property real panelH: Math.round(height * 0.7)
    readonly property real fullW: Math.round(Math.min(panelH * 16 / 9, width - 64))
    readonly property real centerW: Math.min(520, (fullW - 48) * 0.44)
    readonly property real sideW: Math.round((fullW - 48 - centerW - 2 * gap) / 2)
    readonly property bool leftSide: Style.lockShowWeather || Style.lockShowFetch || Style.lockShowMedia
    readonly property bool rightSide: Style.lockShowResources || Style.lockShowCalendar
    readonly property real panelW: 48 + centerW + (leftSide ? sideW + gap : 0) + (rightSide ? sideW + gap : 0)
    readonly property real iconBox: 112

    function focusField() {
        field.input.forceActiveFocus();
    }

    Component.onCompleted: {
        shown = true;
        focusField();
        enterAnim.start();
    }
    onLeavingChanged: {
        if (leaving) {
            enterAnim.stop();
            exitAnim.start();
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // Any key or click: focus the field.
    Keys.onPressed: event => {
        root.focusField();
        event.accepted = false;
    }
    MouseArea {
        anchors.fill: parent
        onPressed: mouse => {
            root.focusField();
            mouse.accepted = false;
        }
    }

    // ---- Background --------------------------------------------------------------------
    // Not scaled itself (its coordinates are the screen's, for the glass);
    // what's inside zooms in a little while locked.
    Item {
        id: background
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: Colors.surface
        }

        Item {
            anchors.fill: parent
            scale: 1.0 + 0.06 * root.presence
            Behavior on scale {
                NumberAnimation { duration: 1200; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            }

            Image {
                id: wall
                anchors.fill: parent
                source: Colors.wallpaper !== "" ? "file://" + Colors.wallpaper : ""
                sourceSize: Qt.size(root.width, root.height)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: wall
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 64
                blur: root.presence * Style.lockWallpaperBlur
                brightness: -0.1 * root.presence
                saturation: root.presence * 0.15
                Behavior on blur {
                    NumberAnimation { duration: 800; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }
                Behavior on brightness {
                    NumberAnimation { duration: 800 }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            opacity: root.presence
            Behavior on opacity {
                NumberAnimation { duration: 600 }
            }
            gradient: Gradient {
                GradientStop { position: 0.0; color: Style.alpha(Colors.scrim, 0.3) }
                GradientStop { position: 0.5; color: Style.alpha(Colors.scrim, 0.05) }
                GradientStop { position: 1.0; color: Style.alpha(Colors.scrim, 0.35) }
            }
        }
    }

    // ---- The islands (like the bar's) --------------------------------------------------
    StatusIsland {
        x: Style.marginEnds
        y: Style.marginEdge
        source: background
        presence: root.presence
        delay: 450
        lockedAt: root.lockedAt
    }

    PowerIsland {
        id: powerIsland
        x: root.width - width - Style.marginEnds
        y: Style.marginEdge
        source: background
        presence: root.presence
        delay: 450 + Style.dropInDelay
        onAction: name => root.power(name)
    }

    // ---- The panel ---------------------------------------------------------------------
    Item {
        id: panel
        anchors.centerIn: parent
        width: root.iconBox
        height: root.iconBox
        scale: 0
        rotation: 180

        property real radius: root.iconBox / 4

        RectangularShadow {
            anchors.fill: parent
            radius: panel.radius
            blur: 30
            offset: Qt.vector2d(0, 6)
            color: Style.alpha(Colors.shadow, 0.45)
        }

        Frosted {
            anchors.fill: parent
            source: background
            area: Qt.rect(panel.x, panel.y, panel.width, panel.height)
            radius: panel.radius
        }

        Icon {
            id: lockIcon
            anchors.centerIn: parent
            name: "lock"
            size: 56
            color: Colors.primary
            rotation: 180
        }

        Row {
            id: content
            anchors.centerIn: parent
            height: root.panelH - 48
            spacing: root.gap
            opacity: 0
            scale: 0

            // Left: weather, system info, now playing.
            Column {
                visible: root.leftSide
                width: root.sideW
                height: parent.height
                spacing: 16

                WeatherCard {
                    id: weather
                    visible: Style.lockShowWeather
                    width: parent.width
                    height: 142
                }
                FetchCard {
                    id: fetch
                    visible: Style.lockShowFetch
                    width: parent.width
                    height: 196
                }
                MediaPanel {
                    visible: Style.lockShowMedia
                    width: parent.width
                    // What the cards above leave.
                    height: parent.height - (weather.visible ? weather.height + parent.spacing : 0)
                        - (fetch.visible ? fetch.height + parent.spacing : 0)
                }
            }

            // Middle: clock, you, the password.
            Item {
                id: middle
                width: root.centerW
                height: parent.height

                LockClock {
                    id: clock
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    now: root.now
                    size: Math.min(156, root.panelH * 0.23)
                }

                // What came in while locked (apps and counts, never the text).
                AwayNotifs {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: clock.bottom
                    anchors.topMargin: 10
                    lockedAt: root.lockedAt
                    textColor: Colors.textOnSurface
                    dimColor: Colors.textOnSurfaceVariant
                    opacity: wanted ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.normal } }
                }

                // Picture, name, password and hint, centred under the clock.
                Item {
                    id: lower
                    anchors.top: clock.bottom
                    anchors.bottom: parent.bottom
                    width: parent.width
                }

                Column {
                    id: who
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: lower.y + (lower.height - (who.height + 22 + field.height + 12 + hint.height)) / 2
                    spacing: 8

                    Avatar {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 96
                        height: 96
                        source: root.avatar
                        userName: root.userName
                        failed: root.authState === "failed"
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.userName
                        role: "headline"
                    }
                }

                PasswordField {
                    id: field
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: who.bottom
                    anchors.topMargin: 22
                    width: Math.min(implicitWidth, parent.width)
                    userName: root.userName
                    authState: root.authState
                    message: root.authMessage
                    onAccepted: root.submit()
                }

                StyledText {
                    id: hint
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: field.bottom
                    anchors.topMargin: 12
                    text: "Enter to unlock  ·  Esc to clear"
                    color: Colors.textOnSurfaceVariant
                    opacity: field.text.length > 0 ? 0 : 0.75
                    Behavior on opacity {
                        NumberAnimation { duration: Motion.fast }
                    }
                }
            }

            // Right: gauges, this month.
            Column {
                visible: root.rightSide
                width: root.sideW
                height: parent.height
                spacing: 16

                ResourcesCard {
                    id: resources
                    visible: Style.lockShowResources
                    width: parent.width
                    height: Style.lockShowCalendar ? 248 : parent.height
                }
                CalendarCard {
                    visible: Style.lockShowCalendar
                    width: parent.width
                    height: parent.height - (resources.visible ? resources.height + parent.spacing : 0)
                    now: root.now
                }
            }
        }
    }

    // ---- Motion (Caelestia's lock, modules/lock/LockSurface.qml) ----------------------
    // Opening: the square scales in while turning half a turn; then the lock
    // turns and fades, the content grows in and the square opens into the panel.
    SequentialAnimation {
        id: enterAnim
        ParallelAnimation {
            NumberAnimation {
                target: panel; property: "scale"; to: 1; duration: Motion.fast
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial
            }
            NumberAnimation {
                target: panel; property: "rotation"; to: 360; duration: Motion.fast
                easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0, 1, 1, 1, 1]
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: lockIcon; property: "rotation"; to: 360; duration: Motion.normal
                easing.type: Easing.BezierSpline; easing.bezierCurve: [0, 0, 0, 1, 1, 1]
            }
            NumberAnimation {
                target: lockIcon; property: "opacity"; to: 0; duration: 200
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects
            }
            NumberAnimation {
                target: content; property: "opacity"; to: 1; duration: 200
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects
            }
            NumberAnimation {
                target: content; property: "scale"; to: 1; duration: Motion.normal
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial
            }
            NumberAnimation {
                target: panel; property: "radius"; to: Style.lockRadius; duration: Motion.normal
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial
            }
            NumberAnimation {
                target: panel; property: "width"; to: root.panelW; duration: Motion.normal
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial
            }
            NumberAnimation {
                target: panel; property: "height"; to: root.panelH; duration: Motion.normal
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial
            }
        }
        ScriptAction {
            script: {
                // From now on the panel follows the settings (and the screen).
                panel.width = Qt.binding(() => root.panelW);
                panel.height = Qt.binding(() => root.panelH);
                panel.radius = Qt.binding(() => Style.lockRadius);
                // Keys typed during the animation already went to the field;
                // make sure it still has focus now that it's visible.
                root.focusField();
            }
        }
    }

    // Unlocking: the panel closes back into the lock square and fades.
    // lock.qml waits for this (~700 ms) before letting go of the lock; the
    // background stays opaque so nothing flashes.
    ParallelAnimation {
        id: exitAnim
        NumberAnimation {
            target: panel; property: "width"; to: root.iconBox; duration: Motion.normal
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial
        }
        NumberAnimation {
            target: panel; property: "height"; to: root.iconBox; duration: Motion.normal
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial
        }
        NumberAnimation {
            target: panel; property: "radius"; to: root.iconBox / 4; duration: Motion.normal
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial
        }
        NumberAnimation {
            target: content; property: "scale"; to: 0; duration: Motion.normal
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial
        }
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 200 }
        NumberAnimation { target: lockIcon; property: "opacity"; to: 1; duration: 400 }
        SequentialAnimation {
            PauseAnimation { duration: 250 }
            NumberAnimation { target: panel; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InOutQuad }
        }
    }
}
