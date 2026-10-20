import QtQuick
import QtQuick.Effects
import Quickshell
import qs.common
import qs.services

// What the desktop shows: the time, big; the date under it; the weather.
// No glass: light text with a soft shadow, so it reads on any wallpaper.
// `align` lines the three up on the left, middle or right.
Item {
    id: root

    property real size: Style.desktopClockScale
    property real align: 0.5            // 0 left, 0.5 middle, 1 right

    readonly property date now: clock.date
    readonly property var dateLocale: Style.clockLocale !== "" ? Qt.locale(Style.clockLocale) : Qt.locale()
    readonly property bool showWeather: Style.desktopClockShowWeather && Weather.enabled && Weather.ready
    // Room around the text for the shadow.
    readonly property int pad: Math.round(24 * size)

    implicitWidth: lines.implicitWidth + pad * 2
    implicitHeight: lines.implicitHeight + pad * 2

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        id: lines
        x: root.pad
        y: root.pad
        spacing: Math.round(4 * root.size)

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.7)
            shadowBlur: 1.0
            shadowVerticalOffset: Math.round(2 * root.size)
            blurMax: 32
        }

        // 14:05, the colon in the accent color like the bar's clock.
        Row {
            x: (lines.width - width) * root.align

            Text {
                id: hours
                text: Qt.formatTime(root.now, "HH")
                color: Colors.textOnSurface
                font.family: Style.font
                font.pixelSize: Math.round(96 * root.size)
                font.variableAxes: ({ "wght": 600, "ROND": 100 })
                font.features: ({ "tnum": 1 })
                renderType: Text.NativeRendering
            }
            Text {
                text: ":"
                color: Colors.primary
                font: hours.font
                renderType: Text.NativeRendering
            }
            Text {
                text: Qt.formatTime(root.now, "mm")
                color: Colors.textOnSurface
                font: hours.font
                renderType: Text.NativeRendering
            }
        }

        // Thursday 15 October
        Text {
            x: (lines.width - width) * root.align
            text: root.dateLocale.toString(root.now, "dddd d MMMM")
            color: Colors.textOnSurface
            opacity: 0.92
            font.family: Style.font
            font.pixelSize: Math.round(22 * root.size)
            font.variableAxes: ({ "wght": 500, "ROND": 100 })
            renderType: Text.NativeRendering
        }

        // ☁ 31°  Partly cloudy · 27° / 33°
        Row {
            x: (lines.width - width) * root.align
            visible: root.showWeather
            spacing: Math.round(8 * root.size)
            topPadding: Math.round(4 * root.size)

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: Weather.icon(Weather.code, Weather.isDay)
                size: Math.round(24 * root.size)
                color: Colors.primary
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Weather.temperature) + "°  " + Weather.words(Weather.code)
                    + "  ·  " + Math.round(Weather.low) + "° / " + Math.round(Weather.high) + "°"
                color: Colors.textOnSurface
                opacity: 0.88
                font.family: Style.font
                font.pixelSize: Math.round(17 * root.size)
                font.variableAxes: ({ "wght": 500, "ROND": 100 })
                renderType: Text.NativeRendering
            }
        }
    }
}
