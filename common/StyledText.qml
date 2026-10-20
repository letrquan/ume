import QtQuick

// Text in the bar's font. Set `weight` for bolder or lighter text.
//
// Plain text unless asked otherwise (textFormat: Text.StyledText): what it
// shows often comes from outside (window and tab titles, notifications,
// songs, Wi-Fi and Bluetooth names), and Qt's default would read markup in
// it, <img src="http://…"> too (a picture fetched from the internet, so a
// web page's title could tell its site you're here, from your own address).
Text {
    // One of Style.textRoles (micro caption label body title headline
    // display): its size and weight.
    property string role: "body"
    property int weight: Style.textWeight(role)

    textFormat: Text.PlainText
    color: Colors.textOnSurface
    font.family: Style.font
    font.pixelSize: Style.textSize(role)
    font.variableAxes: ({ "wght": weight, "ROND": 100 })
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
}
