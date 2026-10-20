import QtQuick
import qs.common

// A round button with one icon, e.g. IconButton { icon: "tune" }.
Clickable {
    id: root

    property string icon: ""
    property color iconColor: Colors.textOnSurface

    Icon {
        name: root.icon
        color: root.iconColor
    }
}
