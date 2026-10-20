import QtQuick

// One item of an island (BarContent's Repeaters): loads the widget for its
// name. Battery and Bluetooth can ask to be left out (`wanted`, e.g. no
// battery); their own `visible` can't be used here, it would follow ours.
Loader {
    required property string modelData
    property Item island
    property var components: ({})

    anchors.verticalCenter: parent?.verticalCenter
    sourceComponent: components[modelData] ?? null
    visible: item !== null && (item.wanted ?? true)
}
