import QtQuick
import Quickshell.Widgets
import qs.common
import qs.control
import qs.services

// One row of the Settings window:
//   Label                                   [↺] [control]
//   short description
// The control changes the knob through Settings (it applies at once); ↺
// appears when you changed it and puts the Style.qml default back.
// Kind "baritems" is the whole width instead: the bar items editor.
Item {
    id: row

    required property var modelData
    readonly property var r: modelData
    readonly property bool knob: r.name !== undefined
    // The knobs ↺ puts back (`resets` when a row sets several together).
    readonly property var resets: r.resets ?? (knob ? [r.name] : [])
    readonly property bool overridden: resets.some(name => Settings.changed(name))
    // The value the shell uses right now (your change or the default).
    readonly property var current: knob ? Style[r.name] : undefined
    readonly property bool wide: r.kind === "baritems"

    function change(v) {
        Settings.set(r.name, v);
    }

    implicitHeight: wide ? editor.implicitHeight : Math.max(r.kind === "wallpaper" ? 112 : 58, texts.implicitHeight + 24)

    Loader {
        id: editor
        active: row.wide
        width: parent.width
        sourceComponent: BarItemsEditor {
            width: row.width
            key: row.r.key ?? ""
        }
    }

    Column {
        id: texts
        visible: !row.wide
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.right: controls.left
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        StyledText {
            width: parent.width
            text: row.r.label
            role: "title"
            elide: Text.ElideRight
        }
        StyledText {
            width: parent.width
            // `status` (e.g. "Not found") replaces the description while it has something to say.
            text: row.r.kind === "info" ? (row.r.text() || "…") : (row.r.status?.() || (row.r.desc ?? ""))
            visible: text !== ""
            role: "caption"
            color: Colors.textOnSurfaceVariant
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
    }

    Row {
        id: controls
        visible: !row.wide
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // Back to the default.
        Clickable {
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: 30
            padding: 0
            visible: opacity > 0.01
            opacity: row.overridden ? 1 : 0
            onClicked: {
                for (const name of row.resets)
                    Settings.reset(name);
            }

            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            Icon {
                name: "restart_alt"
                size: 18
                color: Colors.textOnSurfaceVariant
            }
        }

        Loader {
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: row.r.kind === "number" ? number
                           : row.r.kind === "bool" ? toggle
                           : row.r.kind === "choice" ? choice
                           : row.r.kind === "action" ? action
                           : row.r.kind === "dnd" ? dnd
                           : row.r.kind === "wallpaper" ? wallpaper
                           : row.r.kind === "text" ? textField
                           : null
        }
    }

    Component {
        id: number
        NumberSlider {
            value: row.current
            from: row.r.from
            to: row.r.to
            step: row.r.step
            format: row.r.format
            onMoved: v => row.change(v)
        }
    }

    Component {
        id: toggle
        Toggle {
            checked: row.r.get ? row.r.get() : row.current
            onFlipped: row.r.flip ? row.r.flip() : row.change(!row.current)
        }
    }

    Component {
        id: choice
        Choice {
            choices: row.r.choices
            value: row.current
            onPicked: v => row.change(v)
        }
    }

    // `commit` (optional) handles the typed text instead of storing it as is.
    Component {
        id: textField
        TextSetting {
            // Lists (launcher favorites) show as "foot, zen, …".
            value: Array.isArray(row.current) ? row.current.join(", ") : String(row.current ?? "")
            placeholder: row.r.placeholder ?? ""
            secret: row.r.secret ?? false
            onCommitted: text => {
                if (row.r.commit)
                    row.r.commit(text);
                else if (text.trim() === "")
                    Settings.reset(row.r.name);
                else
                    row.change(text.trim());
            }
        }
    }

    Component {
        id: dnd
        Toggle {
            checked: Notifs.dnd
            onFlipped: Notifs.toggleDnd()
        }
    }

    // A button; `confirm` rows want a second press within 3 s.
    Component {
        id: action
        MouseArea {
            id: button
            property bool armed: false

            width: label.implicitWidth + 32
            height: 32
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (row.r.confirm && !armed) {
                    armed = true;
                    disarm.restart();
                    return;
                }
                armed = false;
                row.r.run();
            }

            Timer {
                id: disarm
                interval: 3000
                onTriggered: button.armed = false
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: button.armed ? Colors.error : Colors.secondaryContainer
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Colors.textOnSurface
                    opacity: button.pressed ? Style.pressTint : button.containsMouse ? Style.hoverTint : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }
            }

            StyledText {
                id: label
                anchors.centerIn: parent
                text: button.armed ? "Press again" : row.r.button
                role: "label"
                color: button.armed ? Colors.textOnError : Colors.textOnSecondaryContainer
            }
        }
    }

    // The current wallpaper, with Choose (the picker) and Shuffle.
    Component {
        id: wallpaper
        Row {
            spacing: 12

            ClippingRectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 144
                height: 90
                radius: 14
                color: Colors.surfaceContainerHigh

                Image {
                    anchors.fill: parent
                    source: Wallpaper.current !== "" ? "file://" + Wallpaper.current : ""
                    sourceSize: Qt.size(288, 180)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                StyledText {
                    width: 150
                    text: Wallpaper.current !== "" ? Wallpaper.label(Wallpaper.current) : ""
                    role: "caption"
                    color: Colors.textOnSurfaceVariant
                    elide: Text.ElideRight
                }
                Row {
                    spacing: 6
                    Clickable {
                        implicitHeight: 30
                        padding: 12
                        onClicked: Wallpaper.setPicker(true)
                        StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Choose…"; role: "label" }
                    }
                    Clickable {
                        implicitHeight: 30
                        padding: 12
                        onClicked: Wallpaper.random()
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: "shuffle"; size: 16 }
                    }
                }
            }
        }
    }
}
