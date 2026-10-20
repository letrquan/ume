import QtQuick
import Quickshell.Services.Pipewire
import qs.common
import qs.services

// Under the volume slider, while apps play sound: "Zen, Spotify ⌄". Click
// it for a slider per app (AppVolumeRow). Hidden when nothing plays or
// Style.ccAppVolumes is off.
Column {
    id: root

    readonly property var streams: AppAudio.streams

    visible: Style.ccAppVolumes && streams.length > 0
    spacing: 2

    // Volume and mute only fill in for tracked nodes.
    PwObjectTracker {
        objects: root.visible ? root.streams : []
    }

    // The header: up to three app icons, their names, an arrow.
    MouseArea {
        id: header
        width: parent.width
        height: 30
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: AppAudio.expanded = !AppAudio.expanded

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Colors.textOnSurface
            opacity: header.pressed ? Style.pressTint : header.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }

        Row {
            id: faces
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: -5

            Repeater {
                model: root.streams.slice(0, 3)

                Rectangle {
                    required property var modelData
                    width: 20
                    height: 20
                    radius: 10
                    color: Colors.surfaceContainerHigh
                    border.width: 1.5
                    border.color: Colors.surfaceContainer

                    // The round chip is its tile; a missing icon gives a letter.
                    AppIcon {
                        anchors.centerIn: parent
                        implicitSize: 14
                        source: AppAudio.appsLoaded >= 0 ? AppAudio.icon(parent.modelData) : ""
                        name: AppAudio.name(parent.modelData)
                        tiled: false
                        letterTile: false
                        letterColor: Colors.textOnSurfaceVariant
                    }
                }
            }
        }

        StyledText {
            anchors.left: faces.right
            anchors.leftMargin: 8
            anchors.right: arrow.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const names = [...new Set(root.streams.map(n => AppAudio.name(n)))];
                return names.length <= 2 ? names.join(", ") : names.slice(0, 2).join(", ") + " +" + (names.length - 2);
            }
            role: "caption"
            color: Colors.textOnSurfaceVariant
            elide: Text.ElideRight
        }

        Icon {
            id: arrow
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            name: "expand_more"
            size: 18
            color: Colors.textOnSurfaceVariant
            rotation: AppAudio.expanded ? 180 : 0
            Behavior on rotation {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }
        }
    }

    // One row per app; grows open and closed.
    Item {
        width: parent.width
        height: AppAudio.expanded ? rows.implicitHeight : 0
        clip: true
        visible: height > 0.5

        Behavior on height {
            NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }

        Column {
            id: rows
            width: parent.width
            opacity: AppAudio.expanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            Repeater {
                model: root.streams

                AppVolumeRow {
                    required property var modelData
                    width: rows.width
                    node: modelData
                }
            }
        }
    }
}
