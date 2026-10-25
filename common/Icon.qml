import QtQuick

// Material Symbols Rounded glyph by name, e.g. Icon { name: "wifi" }.
// Names: https://fonts.google.com/icons
Text {
    property string name: ""
    property real size: Style.iconSize
    // 1 = filled, 0 = outlined (Material Symbols' FILL axis). An icon that
    // shows a state binds it to that state (Style.iconFillStates) and eases
    // between the two; steps of 0.1, so the in-between fonts are few and
    // shared by every icon.
    property real fill: 1
    Behavior on fill {
        NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle }
    }

    text: name
    // A name is only a name (an icon font ligature), never markup.
    textFormat: Text.PlainText
    color: Colors.textOnSurface
    font.family: Style.iconFont
    font.pixelSize: size
    font.variableAxes: ({ "FILL": Style.iconFillStates ? Math.round(fill * 10) / 10 : 1, "wght": 500, "GRAD": 0, "opsz": 24 })
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    renderType: Text.NativeRendering

    Behavior on color { ColorAnimation { duration: Motion.fast } }
}
