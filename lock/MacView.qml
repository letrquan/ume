import QtQuick
import QtQuick.Effects
import Quickshell.Io
import qs.common

// The "mac" lock screen (Settings → Lock screen → Style), like a Mac's:
//
//                         Thursday 15 October
//                               9:41
//                     ╭ ♫ song · artist      ⏯ ╮      (while something plays)
//                 ( ✈ Telegram 5 · m Messenger 2 )      (what came in meanwhile)
//
//
//                                (you)
//                                User
//                        ╭ Enter Password  → ╮
//                                                                 ⏻
//
// Behind: the wallpaper itself, sharp and only a little darker. The time drops in, the
// rest fades up; a wrong password shakes the field. After
// Style.lockHideAfter seconds without input only the time stays; any key or
// mouse move brings the rest back, and typing always goes into the field.
// Unlocking fades everything out while growing it a little, to the plain
// wallpaper (what the desktop shows), like a Mac.
// With face unlock (lock.qml, faceState not "off"): a ring breathes around
// your picture while it looks, the line under the field says how it went,
// and clicking your picture or coming back to a resting lock looks again.
Item {
    id: root

    property string userName: "user"
    property string avatar: ""              // a picture, e.g. ~/.face
    property string authState: "idle"       // idle | busy | failed | success
    property string authMessage: ""
    property alias password: field.text
    property alias powerOpen: powerButton.open
    property date lockedAt: new Date()
    property date now: new Date()
    property string faceState: "off"        // off | idle | looking | failed

    signal submit()
    signal power(string name)
    signal faceTry()

    // The wallpaper is on screen (or failed to load): the greeter fades in then.
    readonly property bool pictureReady: wallpaperImage.status === Image.Ready || wallpaperImage.status === Image.Error

    // How bright the wallpaper is behind each part (0 = dark enough, as it
    // always looked; 1 = bright, the most help): the shade at the top and
    // the bottom, the field's and the pills' tint and the words' shadows
    // follow it (Style.lockFieldContrast). The login screen's chip too.
    readonly property alias light: light
    WallpaperLight {
        id: light
        path: Colors.wallpaper
        aspect: wallpaperImage.status === Image.Ready && wallpaperImage.implicitHeight > 0
            ? wallpaperImage.implicitWidth / wallpaperImage.implicitHeight : 0
        screenAspect: root.height > 0 ? root.width / root.height : 16 / 10
    }
    // A see-through white tint of strength `a`, turned into a darker one
    // (up to `dark`) as the picture behind gets bright (k: 0 → 1).
    function tint(a, dark, k) {
        return Qt.rgba(1 - k, 1 - k, 1 - k, a * (1 - k) + dark * k);
    }

    // shown → everything comes in; leaving → the unlock.
    property bool shown: false
    readonly property bool leaving: authState === "success"
    readonly property real presence: shown && !leaving ? 1 : 0

    // Only the time, after Style.lockHideAfter s without input (never while
    // there's a password typed, it's being checked, or ⏻ is open).
    property bool resting: false
    readonly property bool canRest: Style.lockHideAfter > 0 && field.text === "" && authState === "idle"
        && !powerButton.open && !leaving
    property real lastInput: Date.now()

    function focusField() {
        field.input.forceActiveFocus();
    }
    function activity() {
        lastInput = Date.now();
        resting = false;
    }

    // Your name as the system knows it (the GECOS field), like a Mac shows
    // your full name; the login name, capitalised, if that's all there is.
    property string fullName: userName.charAt(0).toUpperCase() + userName.slice(1)
    Process {
        running: root.userName !== ""
        command: ["getent", "passwd", root.userName]
        stdout: StdioCollector {
            onStreamFinished: {
                const gecos = (this.text.trim().split(":")[4] ?? "").split(",")[0].trim();
                if (gecos !== "" && gecos !== root.userName)
                    root.fullName = gecos;
            }
        }
    }

    Component.onCompleted: {
        shown = true;
        focusField();
        enterAnim.start();
    }
    onPasswordChanged: activity()
    // Back at a lock that showed only the time: look for the face again.
    onRestingChanged: if (!resting) faceTry()

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.now = new Date();
            const quiet = (Date.now() - root.lastInput) / 1000;
            if (root.canRest && quiet >= Style.lockHideAfter)
                root.resting = true;
        }
    }

    // Any key, click or mouse move: everything back, the field focused.
    Keys.onPressed: event => {
        root.activity();
        root.focusField();
        event.accepted = false;
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: root.activity()
        onPressed: mouse => {
            root.activity();
            root.focusField();
            mouse.accepted = false;
        }
    }

    // ---- Background --------------------------------------------------------------------
    // The picture itself, sharp. Its coordinates are the screen's (the frost
    // of the field and the music card samples it).
    Item {
        id: background
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: Colors.surface
        }
        Image {
            id: wallpaperImage
            anchors.fill: parent
            source: Colors.wallpaper !== "" ? "file://" + Colors.wallpaper : ""
            sourceSize: Qt.size(root.width, root.height)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }

        // A little darker, more at the top and the bottom where the text is.
        Item {
            anchors.fill: parent
            opacity: root.presence
            Behavior on opacity {
                NumberAnimation { duration: 600; easing.type: Easing.InOutQuad }
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.1
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.26 + 0.24 * Math.max(light.clock, light.status)) }
                    // On a bright picture the shade reaches down past the time.
                    GradientStop { position: 0.3 + 0.16 * light.clock; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 0.62; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.34 + 0.26 * light.user) }
                }
            }
        }
    }

    // ---- What's on it ------------------------------------------------------------------
    // One layer for everything, so unlocking can fade and grow it as one.
    Item {
        id: stage
        anchors.fill: parent
        transformOrigin: Item.Center

        // 0 → 1 as each part comes in (enterAnim).
        property real clockIn: 0
        property real userIn: 0
        property real cornersIn: 0
        // What hides while resting: everything but the time (and the music).
        property real awakeUi: root.resting ? 0 : 1
        Behavior on awakeUi {
            NumberAnimation { duration: root.resting ? 900 : 250; easing.type: Easing.InOutQuad }
        }

        MacClock {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(root.height * 0.075) - (1 - stage.clockIn) * 28
            size: Math.round(Math.min(150, root.height * 0.15))
            now: root.now
            boost: light.clock
            opacity: stage.clockIn
        }

        MacNowPlaying {
            id: music
            // Settings → Lock screen → Now playing (both styles).
            property real shownAmount: wanted && Style.lockShowMedia ? 1 : 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: clock.y + clock.height + 22
            source: background
            area: Qt.rect(x, y, width, height)
            boost: light.middle
            opacity: stage.clockIn * shownAmount * (root.resting ? 0.7 : 1)
            visible: opacity > 0.01
            scale: 0.92 + 0.08 * shownAmount
            Behavior on shownAmount {
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }
        }

        // What came in while locked (AwayNotifs: apps and counts, never the
        // text), on a frosted pill under the time, or under the music.
        Item {
            id: away
            property real shownAmount: counts.wanted ? 1 : 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: clock.y + clock.height + 22 + music.shownAmount * (music.height + 12)
            width: counts.implicitWidth + 32
            height: 36
            opacity: stage.clockIn * shownAmount * (root.resting ? 0.7 : 1)
            visible: opacity > 0.01
            scale: 0.92 + 0.08 * shownAmount
            Behavior on shownAmount {
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }

            Frosted {
                anchors.fill: parent
                source: background
                area: Qt.rect(away.x, away.y, away.width, away.height)
                radius: height / 2
                tint: root.tint(0.16, 0.38, light.middle)
                saturation: -0.5
            }
            AwayNotifs {
                id: counts
                anchors.centerIn: parent
                lockedAt: root.lockedAt
            }
        }

        // You, your name, the password, what went wrong.
        readonly property real fieldY: Math.round(root.height * 0.845)
        readonly property real userOffset: (1 - stage.userIn) * 22

        // While it looks for your face: a ring breathing around your picture.
        Rectangle {
            id: faceRing
            property real pulse: 0
            anchors.centerIn: picture
            width: picture.width + 12
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: "white"
            visible: root.faceState === "looking"
            opacity: pulse * stage.userIn * stage.awakeUi
            SequentialAnimation on pulse {
                running: faceRing.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0.15; to: 0.8; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.8; to: 0.15; duration: 700; easing.type: Easing.InOutQuad }
            }
        }
        MacAvatar {
            id: picture
            width: 68
            height: 68
            anchors.horizontalCenter: parent.horizontalCenter
            y: nameLabel.y - 8 - height
            source: root.avatar
            name: root.fullName
            opacity: stage.userIn * stage.awakeUi

            // Click: look for the face again.
            MouseArea {
                anchors.fill: parent
                enabled: root.faceState === "idle" || root.faceState === "failed"
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    root.activity();
                    root.focusField();
                    root.faceTry();
                }
            }
        }
        StyledText {
            id: nameLabel
            anchors.horizontalCenter: parent.horizontalCenter
            y: field.y - 14 - height + stage.userOffset
            text: root.fullName
            color: "white"
            role: "title"
            opacity: stage.userIn * stage.awakeUi
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.35 + 0.35 * light.user)
                shadowBlur: 0.5 + 0.3 * light.user
            }
        }
        MacField {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            y: stage.fieldY - height + stage.userOffset
            // The frost samples where the field really sits.
            area: Qt.rect(x, stage.fieldY - height, width, height)
            source: background
            authState: root.authState
            boost: light.field
            opacity: stage.userIn * stage.awakeUi
            onAccepted: root.submit()
            onTyped: root.activity()
        }
        StyledText {
            id: message
            anchors.horizontalCenter: parent.horizontalCenter
            y: field.y + field.height + 10
            readonly property bool failed: root.authState === "failed"
            // The face's line gives way to the password's, and a "not
            // recognized" to typing.
            readonly property string faceText: root.faceState === "looking" ? "Looking for you…"
                : root.faceState === "failed" && field.text === "" ? "Face not recognized · click your picture to try again"
                : ""
            text: failed ? (root.authMessage !== "" ? root.authMessage : "Wrong password")
                : root.authMessage !== "" ? root.authMessage : faceText
            color: "white"
            role: "label"
            opacity: (text !== "" ? 0.95 : 0) * stage.userIn * stage.awakeUi
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.45 + 0.35 * light.user)
                shadowBlur: 0.5 + 0.3 * light.user
            }
        }

        // Corners: keyboard, Wi-Fi, battery at the top right; ⏻ at the bottom right.
        MacStatus {
            x: root.width - width - 18
            y: 12
            boost: light.status
            opacity: stage.cornersIn * stage.awakeUi
        }
        MacPower {
            id: powerButton
            x: root.width - width - 22
            y: root.height - height - 16
            width: implicitWidth
            boost: light.power
            opacity: stage.cornersIn * stage.awakeUi
            onAction: name => root.power(name)
        }
    }

    // ---- Motion --------------------------------------------------------------------------
    // In: the time drops in, you and the field rise, the corners last.
    ParallelAnimation {
        id: enterAnim
        NumberAnimation {
            target: stage; property: "clockIn"; from: 0; to: 1; duration: 700
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
        }
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            NumberAnimation {
                target: stage; property: "userIn"; from: 0; to: 1; duration: 650
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 400 }
            NumberAnimation { target: stage; property: "cornersIn"; from: 0; to: 1; duration: 500 }
        }
    }

    // Out (unlocking): everything grows a little and fades, the picture stays.
    // lock.qml waits ~700 ms for this before letting go of the lock.
    states: State {
        when: root.leaving
        PropertyChanges { target: stage; scale: 1.05; opacity: 0 }
    }
    transitions: Transition {
        NumberAnimation {
            target: stage; properties: "scale,opacity"; duration: 480
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel
        }
    }
}
