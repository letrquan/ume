import QtQuick
import qs.common

// The lock screen, in one of two styles (Settings → Lock screen → Style):
//   "mac"    the time big at the top, you and a small password field at
//            the bottom, nothing else (MacView.qml)
//   "panel"  the frosted panel with the cards (PanelView.qml)
// lock.qml and lock-preview.qml talk to this item only; it hands
// everything to the style that's showing and back.
Item {
    id: root

    property string userName: "user"
    property string avatar: ""              // a picture, e.g. ~/.face
    property string authState: "idle"       // idle | busy | failed | success
    property string authMessage: ""
    property string password: ""
    property bool powerOpen: false
    property date lockedAt: new Date()
    property string faceState: "off"        // off | idle | looking | failed (lock.qml)

    signal submit()
    signal power(string name)
    signal faceTry()                        // look for the face again
    signal woke()                           // a key or a mouse move: you're there

    // In either style. A HoverHandler takes nothing from the items under it.
    // Only a real move counts: while something animates, Qt sends hover
    // events at the same spot every frame.
    HoverHandler {
        property point last: Qt.point(-1, -1)
        onPointChanged: {
            const p = point.position;
            if (last.x >= 0 && Math.abs(p.x - last.x) + Math.abs(p.y - last.y) > 3)
                root.woke();
            last = p;
        }
    }

    readonly property string style: Style.lockStyle === "panel" ? "panel" : "mac"

    // The password and the power menu go both ways (the field types into
    // it, lock.qml clears it after a wrong try), so they're copied by hand
    // instead of bound: a binding would be cut by the first assignment.
    onPasswordChanged: {
        if (view.item && view.item.password !== password)
            view.item.password = password;
        if (password !== "")
            root.woke();
    }
    onPowerOpenChanged: if (view.item && view.item.powerOpen !== powerOpen) view.item.powerOpen = powerOpen

    Loader {
        id: view
        anchors.fill: parent
        focus: true
        sourceComponent: root.style === "panel" ? panelStyle : macStyle
        onLoaded: {
            item.password = root.password;
            item.powerOpen = root.powerOpen;
            // Created inside the Loader: take the keyboard once it's in place.
            Qt.callLater(() => item.focusField());
        }
    }

    Component {
        id: macStyle
        MacView {
            userName: root.userName
            avatar: root.avatar
            authState: root.authState
            authMessage: root.authMessage
            lockedAt: root.lockedAt
            faceState: root.faceState
            onPasswordChanged: if (password !== root.password) root.password = password
            onPowerOpenChanged: if (powerOpen !== root.powerOpen) root.powerOpen = powerOpen
            onSubmit: root.submit()
            onPower: name => root.power(name)
            onFaceTry: root.faceTry()
        }
    }

    Component {
        id: panelStyle
        PanelView {
            userName: root.userName
            avatar: root.avatar
            authState: root.authState
            authMessage: root.authMessage
            lockedAt: root.lockedAt
            onPasswordChanged: if (password !== root.password) root.password = password
            onPowerOpenChanged: if (powerOpen !== root.powerOpen) root.powerOpen = powerOpen
            onSubmit: root.submit()
            onPower: name => root.power(name)
        }
    }
}
