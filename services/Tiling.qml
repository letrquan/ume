pragma Singleton
import QtQuick
import Quickshell

// mango's tiling layouts: the short symbol mango reports ("DW") -> a name and
// a Material Symbols icon, for the bar's layout button and the OSD.
// `mmsg get layouts` lists them; Super+Alt+J (or the button) goes to the next
// one in `circle_layout` (~/.config/mango/config.conf).
Singleton {
    id: root

    readonly property var layouts: ({
        "T": { name: "Tile", icon: "view_quilt" },
        "RT": { name: "Right tile", icon: "vertical_split" },
        "S": { name: "Scroller", icon: "view_carousel" },
        "VS": { name: "Vertical scroller", icon: "view_day" },
        "G": { name: "Grid", icon: "grid_view" },
        "VG": { name: "Vertical grid", icon: "grid_view" },
        "M": { name: "Monocle", icon: "crop_square" },
        "K": { name: "Deck", icon: "auto_awesome_motion" },
        "VK": { name: "Vertical deck", icon: "auto_awesome_motion" },
        "CT": { name: "Center tile", icon: "view_column" },
        "VT": { name: "Vertical tile", icon: "horizontal_split" },
        "DW": { name: "Dwindle", icon: "auto_awesome_mosaic" },
        "F": { name: "Fair", icon: "window" },
        "VF": { name: "Vertical fair", icon: "window" }
    })

    function name(symbol) {
        return layouts[symbol]?.name ?? symbol;
    }
    function icon(symbol) {
        return layouts[symbol]?.icon ?? "dashboard";
    }

    // The next layout in mango's circle_layout list.
    function next() {
        Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"]);
    }
}
