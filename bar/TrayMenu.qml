import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.common

// A tray app's menu, drawn by the shell in the same glass as everything
// else (so the shell doesn't need Qt Widgets for "platform" menus).
// Submenus open in place with a back row; a click outside closes it.
PopupWindow {
    id: root

    required property QsMenuHandle handle

    signal dismissed()

    // Submenus opened so far; the last one is shown.
    property var stack: [handle]
    readonly property var current: stack[stack.length - 1]

    function back() {
        if (stack.length > 1)
            stack = stack.slice(0, -1);
    }

    color: "transparent"
    grabFocus: true
    implicitWidth: card.width
    implicitHeight: card.height
    onVisibleChanged: if (!visible) dismissed()

    QsMenuOpener {
        id: opener
        menu: root.current
    }

    Glass {
        id: card

        width: Math.max(200, Math.min(360, rows.implicitWidth + 12))
        height: rows.implicitHeight + 12
        radius: 18
        color: Style.alpha(Colors.surfaceContainer, 0.92)
        opacity: 0
        Component.onCompleted: opacity = 1

        Behavior on opacity {
            NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }

        // Right click or the back button on a submenu: one level up.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton | Qt.BackButton
            onClicked: root.back()
        }

        Column {
            id: rows
            x: 6
            y: 6
            width: card.width - 12

            TrayMenuRow {
                width: rows.width
                visible: root.stack.length > 1
                label: "Back"
                glyph: "chevron_left"
                onActivated: root.back()
            }

            Repeater {
                model: opener.children

                TrayMenuRow {
                    required property QsMenuEntry modelData

                    width: rows.width
                    separator: modelData.isSeparator
                    enabled: modelData.enabled
                    label: modelData.text
                    iconSource: modelData.icon
                    buttonType: modelData.buttonType
                    checkState: modelData.checkState
                    hasChildren: modelData.hasChildren
                    onActivated: {
                        if (modelData.hasChildren) {
                            root.stack = root.stack.concat([modelData]);
                        } else {
                            modelData.triggered();
                            root.visible = false;
                        }
                    }
                }
            }
        }
    }
}
