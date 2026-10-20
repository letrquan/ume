import QtQuick
import qs.common
import qs.services

// The control center. It grows down out of the right island (MorphCard:
// it starts with the island's exact size and glass, its right edge stays
// put), shows the main page or a detail page (Wi-Fi, Bluetooth, Sound, Phone), and
// shrinks back into the island when closed. Pages slide sideways while the
// card glides to the new page's height.
Item {
    id: root

    // Width of the right island right now: where we start and end.
    property real startWidth: 300
    property bool open: false

    // While true the bar hides the real right island.
    readonly property bool covering: morph.covering
    // Fully back in the island: the window can go.
    readonly property bool settled: morph.settled
    readonly property alias cardItem: morph.card
    readonly property string page: ControlState.page

    signal closeRequested()

    // The detail page keeps showing while it slides away.
    property string detail: "wifi"
    onPageChanged: if (page !== "main") detail = page

    readonly property real pad: Style.ccPadding
    readonly property real contentHeight: page === "main" ? mainPage.implicitHeight : (details.item?.implicitHeight ?? 0)

    MorphCard {
        id: morph

        anchors.fill: parent
        grow: "right"
        fromX: width - Style.marginEnds - root.startWidth
        fromY: Style.marginEdge
        fromWidth: root.startWidth
        toWidth: Style.ccWidth
        toHeight: root.contentHeight + root.pad * 2
        radius: Style.ccRadius
        glassOpacity: Style.ccOpacity
        open: root.open

        // Clicks on the card stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        MainPage {
            id: mainPage
            x: root.pad + (root.page === "main" ? 0 : -60)
            y: root.pad
            width: Style.ccWidth - root.pad * 2
            opacity: root.page === "main" ? 1 : 0
            visible: opacity > 0.01

            Behavior on x {
                NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            }
            Behavior on opacity {
                NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            }
        }

        Loader {
            id: details
            x: root.pad + (root.page === "main" ? 60 : 0)
            y: root.pad
            width: Style.ccWidth - root.pad * 2
            active: root.page !== "main" || opacity > 0.01
            opacity: root.page === "main" ? 0 : 1
            sourceComponent: root.detail === "wifi" ? wifiPage : root.detail === "bluetooth" ? bluetoothPage
                : root.detail === "phone" ? phonePage : audioPage

            Behavior on x {
                NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            }
            Behavior on opacity {
                NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            }
        }
    }

    Component { id: wifiPage; WifiPage {} }
    Component { id: bluetoothPage; BluetoothPage {} }
    Component { id: audioPage; AudioPage {} }
    Component { id: phonePage; PhonePage {} }
}
