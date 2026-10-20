import QtQuick
import qs.common
import qs.services

// Sound devices: pick where sound goes out and comes in.
Column {
    id: root

    spacing: 6

    PageHeader {
        width: parent.width
        title: "Sound"
    }

    Flickable {
        width: parent.width
        height: Math.min(contentHeight, 7 * 50)
        contentHeight: lists.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: lists
            width: parent.width
            spacing: 2

            StyledText {
                leftPadding: 12
                bottomPadding: 2
                text: "Output"
                role: "label"
                color: Colors.primary
            }

            Repeater {
                model: ControlState.sinks

                ListItem {
                    required property var modelData
                    width: lists.width
                    icon: (modelData.name ?? "").includes("bluez") ? "headphones" : (modelData.name ?? "").includes("hdmi") ? "tv" : "speaker"
                    label: ControlState.nodeName(modelData)
                    current: modelData === ControlState.sink
                    trailing: current ? "check" : ""
                    onClicked: ControlState.useSink(modelData)
                }
            }

            // Fuller sound from the built-in speakers (headphones and
            // Bluetooth always get the plain sound).
            Item {
                width: lists.width
                height: eqRow.implicitHeight

                ListItem {
                    id: eqRow
                    anchors.fill: parent
                    icon: "graphic_eq"
                    label: "Speaker EQ"
                    detail: (ControlState.sink?.name ?? "").includes("Speaker") ? "Fuller sound" : "Built-in speakers only"
                    onClicked: ControlState.setSpeakerEq(!ControlState.speakerEq)
                }
                Toggle {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    checked: ControlState.speakerEq
                    onFlipped: ControlState.setSpeakerEq(!ControlState.speakerEq)
                }
            }

            StyledText {
                leftPadding: 12
                topPadding: 8
                bottomPadding: 2
                text: "Input"
                role: "label"
                color: Colors.primary
            }

            Repeater {
                model: ControlState.sources

                ListItem {
                    required property var modelData
                    width: lists.width
                    icon: (modelData.name ?? "").includes("bluez") ? "headset_mic" : "mic"
                    label: ControlState.nodeName(modelData)
                    current: modelData === ControlState.source
                    trailing: current ? "check" : ""
                    onClicked: ControlState.useSource(modelData)
                }
            }
        }
    }
}
