import QtQuick
import qs.common
import qs.services

// The wallpaper picker: folder chips, a shuffle button and a grid of
// thumbnails. The current wallpaper has a ring and a check. Click (or
// arrows + Enter) to change; the new one spreads out from the thumbnail you
// picked. Esc closes. Plain QtQuick, so it can be previewed outside the shell.
// The glass around it is PickerWindow's MorphCard.
Item {
    id: root

    property string folder: ""          // "" = all
    readonly property real thumbW: Style.pickerThumbWidth
    readonly property real thumbH: Math.round(thumbW * 0.625)
    readonly property real gap: 10
    // Thumbs sit 8 + gap px inside the card: their corners follow its corner.
    readonly property real thumbRadius: Style.inner(Style.launcherRadius, 8 + gap)
    readonly property var folders: {
        const set = [];
        for (const p of Wallpaper.list) {
            const rel = p.substring(Style.wallpaperDir.length + 1);
            const f = rel.includes("/") ? rel.split("/")[0] : "";
            if (f !== "" && !set.includes(f))
                set.push(f);
        }
        return set;
    }
    readonly property var shown: Wallpaper.list.filter(p => folder === "" || p.startsWith(Style.wallpaperDir + "/" + folder + "/"))

    signal closeRequested()

    function focusGrid() {
        grid.forceActiveFocus();
        selectCurrent();
    }

    // Start on the current wallpaper (or the first one), scrolled into view.
    function selectCurrent() {
        grid.currentIndex = Math.max(0, shown.indexOf(Wallpaper.current));
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
    }

    // The list arrives a moment after opening, and changes with the folder.
    onShownChanged: Qt.callLater(selectCurrent)

    function pick(index) {
        const path = shown[index];
        const cell = grid.itemAtIndex(index);
        if (!path)
            return;
        // Spread the new one from the thumbnail (as a fraction of the screen).
        const win = root.Window.window;
        let from = Qt.point(0.5, 0);
        if (cell && win) {
            const c = cell.mapToItem(null, cell.width / 2, cell.height / 2);
            from = Qt.point(c.x / win.width, c.y / win.height);
        }
        Wallpaper.set(path, from);
    }

    implicitWidth: Style.pickerColumns * (thumbW + gap) + gap + 16
    implicitHeight: header.height + 12 + Math.min(Style.pickerRows, Math.ceil(shown.length / Style.pickerColumns)) * (thumbH + gap) + gap + 8

    // Clicks on the panel stay on the panel.
    MouseArea {
        anchors.fill: parent
    }

    // ---- Header: title, folders, shuffle -----------------------------------------
    Item {
        id: header
        x: 16
        y: 12
        width: parent.width - 32
        height: 34

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                rightPadding: 8
                text: "Wallpapers"
                role: "title"
            }

            Repeater {
                model: [""].concat(root.folders)

                Item {
                    id: chip
                    required property var modelData
                    readonly property bool active: root.folder === modelData

                    anchors.verticalCenter: parent.verticalCenter
                    width: chipButton.width
                    height: chipButton.height

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: chip.active ? Colors.primary : Style.alpha(Colors.textOnSurface, 0.08)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    Clickable {
                        id: chipButton
                        implicitHeight: 28
                        padding: 12
                        onClicked: root.folder = chip.modelData

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData === "" ? "All" : chip.modelData.replace(/[-_]+/g, " ")
                            role: "label"
                            color: chip.active ? Colors.textOnPrimary : Colors.textOnSurface
                        }
                    }
                }
            }
        }

        // Shuffle: a random one from all folders.
        Clickable {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: 32
            padding: 10
            onClicked: Wallpaper.random()

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "shuffle"
                size: 18
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Shuffle"
                role: "label"
            }
        }
    }

    // ---- Thumbnails ----------------------------------------------------------------
    GridView {
        id: grid

        x: 8 + root.gap / 2
        y: header.y + header.height + 12
        width: Style.pickerColumns * (root.thumbW + root.gap)
        height: parent.height - y - 8
        cellWidth: root.thumbW + root.gap
        cellHeight: root.thumbH + root.gap
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.shown
        keyNavigationEnabled: true
        highlightFollowsCurrentItem: false

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.closeRequested();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.pick(grid.currentIndex);
                event.accepted = true;
            }
        }

        delegate: Item {
            id: cell

            required property string modelData
            required property int index
            readonly property bool isCurrent: modelData === Wallpaper.current
            readonly property bool focused: GridView.isCurrentItem && grid.activeFocus
            readonly property string thumb: {
                Wallpaper.thumbsVersion;
                return Wallpaper.thumbs[modelData] ?? "";
            }

            width: grid.cellWidth
            height: grid.cellHeight

            Item {
                id: card
                x: root.gap / 2
                y: root.gap / 2
                width: root.thumbW
                height: root.thumbH
                scale: mouse.pressed ? 0.96 : mouse.containsMouse || cell.focused ? 1.04 : 1

                Behavior on scale {
                    NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                }

                // The picture with rounded corners, drawn straight from its
                // texture (RoundedTexture). A ClippingRectangle made two
                // offscreen copies of every thumb as the picker opened.
                Rectangle {
                    anchors.fill: parent
                    radius: root.thumbRadius
                    color: Colors.surfaceContainerHigh
                }
                Image {
                    id: thumbPicture
                    anchors.fill: parent
                    source: cell.thumb
                    sourceSize: Qt.size(352, 220)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                RoundedTexture {
                    anchors.fill: parent
                    source: thumbPicture
                    radius: root.thumbRadius
                    opacity: thumbPicture.status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                // Name, on hover. Same corners as the picture (the top ones
                // are in the gradient's see-through end).
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 30
                    radius: root.thumbRadius
                    opacity: mouse.containsMouse || cell.focused ? 1 : 0
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.6) }
                    }
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                    StyledText {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 8
                        text: Wallpaper.label(cell.modelData).split("  ·  ").pop()
                        role: "label"
                        color: "white"
                        elide: Text.ElideRight
                    }
                }

                // Ring: current wallpaper (primary) or keyboard focus (soft).
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: root.thumbRadius + 3
                    color: "transparent"
                    border.width: cell.isCurrent ? 3 : 2
                    border.color: cell.isCurrent ? Colors.primary : Style.alpha(Colors.textOnSurface, 0.5)
                    visible: cell.isCurrent || cell.focused
                }

                // Check badge on the current one.
                Item {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 6
                    width: 24
                    height: 24
                    visible: cell.isCurrent

                    Shape {
                        anchors.fill: parent
                        shape: "Cookie9Sided"
                        color: Colors.primary
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: "check"
                        size: 15
                        color: Colors.textOnPrimary
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        grid.currentIndex = cell.index;
                        root.pick(cell.index);
                    }
                }
            }
        }
    }
}
