import QtQuick
import qs.common

// The big time with rolling digits (the bar's RollingDigit) and a softly
// breathing colon, then the date. 24-hour or 12-hour and the date's
// language follow the bar's clock (Style.clock24h, Style.clockLocale).
Column {
    id: root

    property date now: new Date()
    property real size: 156

    readonly property var dateLocale: Style.clockLocale !== "" ? Qt.locale(Style.clockLocale) : Qt.locale()
    readonly property int hours: Style.clock24h ? now.getHours() : (now.getHours() + 11) % 12 + 1
    // 12-hour: no leading zero ("9:41"), 24-hour: always two digits.
    readonly property string hh: Style.clock24h ? String(hours).padStart(2, "0") : String(hours).padStart(2, " ")
    readonly property string mm: String(now.getMinutes()).padStart(2, "0")

    property font digitFont
    digitFont.family: Style.font
    digitFont.pixelSize: root.size
    digitFont.variableAxes: ({ "wght": 420, "ROND": 100, "wdth": 100, "opsz": 144 })
    digitFont.features: ({ "tnum": 1 })

    spacing: -Math.round(size / 11)

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2

        RollingDigit {
            visible: root.hh[0] !== " "
            digit: root.hh[0]
            font: root.digitFont
            color: Colors.primary
        }
        RollingDigit {
            digit: root.hh[1]
            font: root.digitFont
            color: Colors.primary
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -root.size / 16
            text: ":"
            font: root.digitFont
            color: Colors.tertiary
            renderType: Text.NativeRendering

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 1000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
            }
        }

        RollingDigit {
            digit: root.mm[0]
            font: root.digitFont
            color: Colors.primary
        }
        RollingDigit {
            digit: root.mm[1]
            font: root.digitFont
            color: Colors.primary
        }

        StyledText {
            visible: !Style.clock24h
            // Sits on the digits' baseline, roughly.
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.size * 0.2
            leftPadding: 10
            text: root.now.getHours() < 12 ? "AM" : "PM"
            font.pixelSize: root.size / 5
            weight: 600
            color: Colors.tertiary
        }
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property string raw: root.dateLocale.toString(root.now, "dddd, d MMMM")
        text: raw.charAt(0).toUpperCase() + raw.slice(1)
        role: "display"
        weight: 500
        opacity: 0.9
    }
}
