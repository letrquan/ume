import QtQuick
import qs.common
import qs.services

// What a right-click on a notification (or on an app's group in the list)
// offers, as a row of pills that slides open in the card:
//   ( 🔕 Mute Grab )  ( 📥 List only )  ( ✕ )      "List only": no popup or sound
// The choice is kept in Style.notifRules (Notifs.setRule); Settings →
// Notifications lists the apps with a rule and takes it away again.
Flow {
    id: root

    required property string app
    // Something was picked, or ✕: the card closes the menu.
    signal done()

    readonly property string rule: Notifs.ruleFor(app)
    // A long app name is cut short on the button.
    readonly property string shortApp: app.length > 24 ? app.substring(0, 23) + "…" : app

    spacing: 6

    Repeater {
        model: [
            { icon: "notifications_off", text: "Mute " + root.shortApp, rule: "mute" },
            root.rule === "quiet"
                ? { icon: "notifications_active", text: "Popups again", rule: "" }
                : { icon: "inbox", text: "List only", rule: "quiet" }
        ]

        MouseArea {
            id: pill
            required property var modelData

            width: pillRow.implicitWidth + 24
            height: 28
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                // The rule changes this menu's buttons (this one goes): done
                // first, then the rule, with nothing of this button after.
                const app = root.app, rule = modelData.rule;
                root.done();
                Notifs.setRule(app, rule);
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Colors.secondaryContainer
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Colors.textOnSurface
                    opacity: pill.pressed ? Style.pressTint : pill.containsMouse ? Style.hoverTint : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }
            }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 4
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: pill.modelData.icon
                    size: 15
                    color: Colors.textOnSecondaryContainer
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.modelData.text
                    role: "label"
                    color: Colors.textOnSecondaryContainer
                }
            }
        }
    }

    // Never mind. (In an Item: Clickable centres itself on its parent.)
    Item {
        width: 28
        height: 28

        Clickable {
            implicitHeight: 28
            padding: 6
            onClicked: root.done()

            Icon {
                name: "close"
                size: 16
                color: Colors.textOnSurfaceVariant
            }
        }
    }
}
