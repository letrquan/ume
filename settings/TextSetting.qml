import QtQuick
import qs.common

// A one-line text setting (a folder, a font, a place): type, then Enter or
// click elsewhere to keep it; Esc puts back what was there.
// TextSetting { value: ...; placeholder: "..."; onCommitted: text => ... }
Item {
    id: root

    property string value: ""
    property string placeholder: ""
    // Hidden as dots unless you're typing in it (e.g. a calendar's secret address).
    property bool secret: false

    signal committed(string text)

    implicitWidth: 260
    implicitHeight: 32

    // A new value from elsewhere (reset, a found place): show it, unless
    // you're typing. Long ones show their start.
    onValueChanged: {
        if (!input.activeFocus) {
            input.text = value;
            input.cursorPosition = 0;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Style.alpha(Colors.textOnSurface, input.activeFocus ? 0.12 : 0.08)
        border.width: input.activeFocus ? 2 : 0
        border.color: Colors.primary
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        verticalAlignment: TextInput.AlignVCenter
        text: root.value
        echoMode: root.secret && !activeFocus ? TextInput.Password : TextInput.Normal
        Component.onCompleted: cursorPosition = 0
        clip: true
        selectByMouse: true
        color: Colors.textOnSurface
        selectionColor: Style.alpha(Colors.primary, 0.4)
        selectedTextColor: Colors.textOnSurface
        font.family: Style.font
        font.pixelSize: Style.textSize("body")

        onEditingFinished: {
            if (text !== root.value)
                root.committed(text);
        }
        Keys.onEscapePressed: event => {
            text = root.value;
            focus = false;
            event.accepted = true;      // Esc here doesn't close the window
        }
        // ↑↓ would change the section while typing.
        Keys.onUpPressed: event => event.accepted = true
        Keys.onDownPressed: event => event.accepted = true
    }

    StyledText {
        anchors.left: input.left
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text === "" && !input.activeFocus
        text: root.placeholder
        font.pixelSize: Style.textSize("body")
        color: Colors.textOnSurfaceVariant
    }
}
