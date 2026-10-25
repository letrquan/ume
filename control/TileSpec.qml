import QtQuick

// One control center tile, as control/ControlTiles.qml lists them: the id
// Style.controlTiles uses, the name, symbol and a line about it for the
// editors (the control center's tray, Settings), when it can show, and
// the tile itself (a control/Tile, written inside the TileSpec).
QtObject {
    property string tileId: ""
    property string label: ""
    property string icon: ""
    property string desc: ""
    // Whether it shows right now (e.g. only once its app is installed): a
    // function, only asked by the control center itself, so what it reads
    // starts no sooner than the tile does. null = always.
    property var available: null
    // The tile. Made while the control center is open and the tile is in
    // Style.controlTiles (also while `available` says no, like before).
    default property Component tile
}
