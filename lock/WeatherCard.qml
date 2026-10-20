import QtQuick
import qs.common
import qs.services

// The weather, same as under the calendar: the sky in a cookie, the
// temperature, the place, today's high/low and the next few hours. From the
// shell's saved forecast (services/Weather.qml; in the lock it only reads).
LockCard {
    id: root

    readonly property bool ready: Style.weatherEnabled && Weather.ready

    Item {
        id: now
        width: parent.width
        height: 48

        Item {
            id: badge
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44

            Shape {
                anchors.fill: parent
                shape: "Cookie12Sided"
                color: Colors.secondaryContainer
            }
            Icon {
                anchors.centerIn: parent
                name: root.ready ? Weather.icon(Weather.code, Weather.isDay) : "cloud_off"
                size: 24
                color: Colors.textOnSecondaryContainer
            }
        }

        StyledText {
            id: temp
            anchors.left: badge.right
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.ready ? Math.round(Weather.temperature) + "°" : "--°"
            font.pixelSize: Style.lockWeatherTempSize
            weight: 700
            font.features: ({ "tnum": 1 })
        }

        Column {
            anchors.left: temp.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            StyledText {
                width: parent.width
                text: root.ready ? Weather.words(Weather.code) : "No weather yet"
                role: "label"
                elide: Text.ElideRight
            }
            StyledText {
                width: parent.width
                text: Style.weatherCity
                role: "caption"
                color: Colors.textOnSurfaceVariant
                elide: Text.ElideRight
            }
            StyledText {
                width: parent.width
                visible: root.ready
                text: "H " + Math.round(Weather.high) + "°  L " + Math.round(Weather.low) + "°"
                role: "caption"
                color: Colors.textOnSurfaceVariant
                font.features: ({ "tnum": 1 })
            }
        }
    }

    // The next few hours.
    Row {
        anchors.bottom: parent.bottom
        width: parent.width
        visible: root.ready && hours.count > 0

        Repeater {
            id: hours
            model: root.ready ? Weather.nextHours(4) : []

            Column {
                required property var modelData
                width: parent.width / Math.max(1, hours.count)
                spacing: 2

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.modelData.hour
                    role: "caption"
                    color: Colors.textOnSurfaceVariant
                }
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: Weather.icon(parent.modelData.code, parent.modelData.isDay)
                    size: 18
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Math.round(parent.modelData.temp) + "°"
                    role: "label"
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }
}
