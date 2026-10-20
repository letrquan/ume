import QtQuick
import QtQuick.Effects
import qs.common

// The mac style's time: the date small on top and the time huge under it,
// in white that lets a little of the picture through, with a soft shadow
// so it still reads on a bright wallpaper. 12-hour time has no AM/PM and no
// leading zero ("9:41"), like a Mac. The date's language follows the bar's
// clock (Style.clockLocale).
Item {
    id: root

    property date now: new Date()
    property real size: 144
    // 0 → 1 as the picture behind gets bright: a stronger shadow.
    property real boost: 0

    // Style.lockClockFont, else SF Pro Rounded when it's installed (the
    // Mac's own), else the bar's font made round and heavy.
    readonly property string family: Style.lockClockFont !== "" ? Style.lockClockFont
        : Qt.fontFamilies().indexOf("SF Pro Rounded") >= 0 ? "SF Pro Rounded" : Style.font
    readonly property var dateLocale: Style.clockLocale !== "" ? Qt.locale(Style.clockLocale) : Qt.locale()
    readonly property string time: {
        const h = now.getHours();
        const m = String(now.getMinutes()).padStart(2, "0");
        return Style.clock24h ? String(h).padStart(2, "0") + ":" + m : ((h + 11) % 12 + 1) + ":" + m;
    }
    readonly property string date: {
        const raw = dateLocale.toString(now, "dddd d MMMM");
        return raw.charAt(0).toUpperCase() + raw.slice(1);
    }

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.28 + 0.32 * root.boost)
        shadowBlur: 0.7 + 0.3 * root.boost
        shadowVerticalOffset: 2
    }

    Column {
        id: column
        spacing: -Math.round(root.size * 0.06)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.date
            color: Qt.rgba(1, 1, 1, 0.88)
            font.family: root.family
            font.pixelSize: Math.round(root.size * 0.15)
            font.weight: Font.DemiBold
            font.variableAxes: ({ "wght": 600, "ROND": 100 })
            renderType: Text.NativeRendering
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.time
            color: Qt.rgba(1, 1, 1, 0.9)
            font.family: root.family
            font.pixelSize: root.size
            font.weight: Font.Bold
            font.variableAxes: ({ "wght": 760, "ROND": 100, "opsz": 144 })
            font.features: ({ "tnum": 1 })
            renderType: Text.NativeRendering
        }
    }
}
