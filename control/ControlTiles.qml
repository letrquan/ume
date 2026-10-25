pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.common
import qs.services

// Every tile the control center can show, and the edits its Edit mode and
// the Settings window make. Which tiles show, in which order, is
// Style.controlTiles (a list of the ids below); control/TileGrid.qml draws
// them two to a row. An id that isn't here is skipped, and so is one listed
// twice. Tiles not in the list wait in the "Add tiles" tray.
//
// ADDING A TILE is one block at the end of the Shelf below (just before its
// closing brace; nothing else to touch: it shows up in the control center's
// tray and in Settings → Control center):
//
//         // <What it is, in a line or two.>
//         TileSpec {
//             tileId: "timer"                       // new, unique, never renamed (it's saved)
//             label: "Timer"                        // for the tray and Settings
//             icon: "timer"                         // Material Symbols name
//             desc: "Counts down; click to start"   // for Settings
//             available: () => Timers.ready         // optional: hidden while false
//
//             Tile {                                // control/Tile.qml; no width (the grid sizes it)
//                 icon: "timer"
//                 label: "Timer"
//                 detail: Timers.left
//                 active: Timers.running
//                 onToggled: Timers.toggle()
//             }
//         }
//
// It isn't shown until it's added (tray or Settings); to show it to everyone
// from the start, also add its id to Style.controlTiles' default.
Singleton {
    id: root

    // The TileSpecs live on a shelf of our own: a Singleton's own children
    // can't be read back as a list.
    component Shelf: QtObject {
        default property list<QtObject> tiles
    }

    // The tiles, in this file's order (the tray and Settings list them so).
    readonly property var specs: {
        const out = [];
        for (let i = 0; i < shelf.tiles.length; i++) {
            const c = shelf.tiles[i];
            if (c && typeof c.tileId === "string" && c.tileId !== "")
                out.push(c);
        }
        return out;
    }
    readonly property var ids: specs.map(s => s.tileId)

    function spec(id) {
        return specs.find(s => s.tileId === id) ?? null;
    }

    // Shown, in order: known ids only, each once.
    readonly property var chosen: {
        const list = Array.isArray(Style.controlTiles) ? Style.controlTiles : [];
        const out = [];
        for (const id of list)
            if (ids.includes(id) && !out.includes(id))
                out.push(id);
        return out;
    }
    // Not shown (the tray, Settings' "Not shown").
    readonly property var hidden: ids.filter(id => !chosen.includes(id))

    // ---- Edits (each saves at once) ------------------------------------------------
    function save(list) {
        Settings.set("controlTiles", list.slice());
    }
    function add(id) {
        if (ids.includes(id) && !chosen.includes(id))
            save(chosen.concat([id]));
    }
    function remove(id) {
        if (chosen.includes(id))
            save(chosen.filter(i => i !== id));
    }
    // One place earlier (-1) or later (+1).
    function move(index, by) {
        const list = chosen.slice();
        const to = index + by;
        if (index < 0 || index >= list.length || to < 0 || to >= list.length)
            return;
        [list[index], list[to]] = [list[to], list[index]];
        save(list);
    }
    function reset() {
        Settings.reset("controlTiles");
    }

    // ---- The tiles (one TileSpec each; a new one goes at the end) ----------------------
    Shelf {
        id: shelf

        TileSpec {
            tileId: "wifi"
            label: "Wi-Fi"
            icon: "wifi"
            desc: "On and off; the arrow: networks, and Share as a QR code"

            Tile {
                icon: ControlState.wiredDevice ? "lan" : Networking.wifiEnabled ? "wifi" : "wifi_off"
                label: ControlState.wiredDevice ? "Ethernet" : "Wi-Fi"
                detail: ControlState.wiredDevice ? "Connected"
                      : !Networking.wifiEnabled ? "Off"
                      : ControlState.wifiNetwork?.name ?? "Not connected"
                active: ControlState.wiredDevice !== null || Networking.wifiEnabled
                hasPage: true
                onToggled: ControlState.setWifi(!Networking.wifiEnabled)
                onOpenPage: ControlState.page = "wifi"
            }
        }

        TileSpec {
            tileId: "bluetooth"
            label: "Bluetooth"
            icon: "bluetooth"
            desc: "On and off; the arrow: devices"

            Tile {
                readonly property bool powered: ControlState.adapter?.enabled ?? false
                icon: !powered ? "bluetooth_disabled" : ControlState.btConnected.length > 0 ? "bluetooth_connected" : "bluetooth"
                label: "Bluetooth"
                detail: !ControlState.adapter ? "No adapter"
                      : !powered ? "Off"
                      : ControlState.btConnected.length === 1
                        ? ControlState.btConnected[0].name + (Peripherals.levelOf(ControlState.btConnected[0]) !== "" ? " · " + Peripherals.levelOf(ControlState.btConnected[0]) : "")
                      : ControlState.btConnected.length > 1 ? ControlState.btConnected.length + " devices"
                      : "On"
                active: powered
                hasPage: ControlState.adapter !== null
                onToggled: ControlState.setBluetooth(!powered)
                onOpenPage: ControlState.page = "bluetooth"
            }
        }

        TileSpec {
            tileId: "silent"
            label: "Silent"
            icon: "do_not_disturb_on"
            desc: "Notifications go to the list without popping up"

            Tile {
                icon: Notifs.dnd ? "do_not_disturb_on" : "notifications"
                label: "Silent"
                detail: Notifs.dnd ? "Notifications muted" : "Off"
                active: Notifs.dnd
                onToggled: Notifs.toggleDnd()
            }
        }

        TileSpec {
            tileId: "awake"
            label: "Keep awake"
            icon: "coffee"
            desc: "The screen stays on and nothing locks"

            Tile {
                icon: "coffee"
                label: "Keep awake"
                detail: Idle.keepAwake ? "Screen stays on" : "Off"
                active: Idle.keepAwake
                onToggled: Idle.keepAwake = !Idle.keepAwake
            }
        }

        // Right-click: all the time <-> at night.
        TileSpec {
            tileId: "nightlight"
            label: "Night light"
            icon: "nightlight"
            desc: "Warmer colors; right click: all the time or at night"

            Tile {
                icon: "nightlight"
                label: "Night light"
                detail: NightLight.detail
                active: NightLight.isOn && NightLight.available
                hasSecondary: true
                onToggled: NightLight.toggle()
                onSecondary: NightLight.cycle()
            }
        }

        // Click: dark <-> light; right click: auto (light by day).
        TileSpec {
            tileId: "darkmode"
            label: "Dark mode"
            icon: "dark_mode"
            desc: "Dark or light; right click: auto (light by day)"

            Tile {
                icon: Theme.dark ? "dark_mode" : "light_mode"
                label: "Dark mode"
                detail: Theme.mode === "auto" ? "Auto · " + (Theme.dark ? "night" : "day") : (Theme.dark ? "On" : "Off")
                active: Theme.dark
                hasSecondary: true
                onToggled: Theme.toggle()
                onSecondary: Theme.cycleAuto()
            }
        }

        TileSpec {
            tileId: "screenshot"
            label: "Screenshot"
            icon: "screenshot_region"
            desc: "Pick a region of the screen"

            Tile {
                icon: "screenshot_region"
                label: "Screenshot"
                detail: "Pick a region"
                onToggled: {
                    ControlState.close();
                    shotLater.start();      // once the control center is out of the picture
                }

                Timer {
                    id: shotLater
                    interval: Motion.morphOut + 150
                    onTriggered: Screenshot.region()
                }
            }
        }

        // Screen recording: click records the screen, right click (or a
        // long press) picks a region first; click again to stop.
        TileSpec {
            tileId: "record"
            label: "Record"
            icon: "screen_record"
            desc: "Record the screen; right click: a region"

            Tile {
                icon: "screen_record"
                label: Recorder.recording ? "Recording" : "Record"
                detail: Recorder.recording ? Recorder.elapsedText + " · click to stop" : "Right-click: a region"
                active: Recorder.recording
                hasSecondary: true
                onToggled: {
                    if (Recorder.recording) {
                        Recorder.stop();
                        return;
                    }
                    ControlState.close();
                    Recorder.startSoon("screen");
                }
                onSecondary: {
                    if (Recorder.recording) {
                        Recorder.stop();
                        return;
                    }
                    ControlState.close();
                    Recorder.startSoon("region");
                }
            }
        }

        TileSpec {
            tileId: "power"
            label: "Power mode"
            icon: "balance"
            desc: "Saver, balanced, performance: click for the next"

            Tile {
                readonly property int profile: PowerProfiles.profile
                icon: profile === PowerProfile.PowerSaver ? "eco" : profile === PowerProfile.Performance ? "bolt" : "balance"
                label: "Power mode"
                detail: profile === PowerProfile.PowerSaver ? "Saver" : profile === PowerProfile.Performance ? "Performance" : "Balanced"
                active: profile !== PowerProfile.Balanced
                onToggled: ControlState.nextProfile()
            }
        }

        // Turning the screen with the tablet (Settings → On-screen keyboard →
        // Tablet): only while that's on. Click: hold the screen as it is.
        TileSpec {
            tileId: "rotate"
            label: "Auto-rotate"
            icon: "mobile_rotate"
            desc: "Hold the screen as it is; shows while turning with the tablet is on"
            available: () => AutoRotate.enabled

            Tile {
                icon: AutoRotate.locked ? "mobile_rotate_lock" : "mobile_rotate"
                label: "Auto-rotate"
                detail: AutoRotate.locked ? "Held as it is" : AutoRotate.active ? "On" : "In tablet mode"
                active: !AutoRotate.locked
                onToggled: AutoRotate.toggleLock()
            }
        }

        // Your phone (KDE Connect): only once it's installed. Click: its page.
        TileSpec {
            tileId: "phone"
            label: "Phone"
            icon: "smartphone"
            desc: "Your phone through KDE Connect, once it's installed"
            available: () => Style.ccPhone && Phone.installed

            Tile {
                icon: Phone.connected ? Phone.glyphFor(Phone.device) : "phonelink_off"
                label: Phone.device?.name ?? "Phone"
                detail: Phone.summary
                active: Phone.connected
                hasPage: true
                onToggled: ControlState.page = "phone"
                onOpenPage: ControlState.page = "phone"
                Component.onCompleted: Phone.use(true)
                Component.onDestruction: Phone.use(false)
            }
        }

        // Tailscale: only once it's installed. Click: on / off (once you're
        // its operator; until then the page, which says how); arrow: its page.
        TileSpec {
            tileId: "tailscale"
            label: "Tailscale"
            icon: "vpn_lock"
            desc: "On and off, your devices, the exit node, once it's installed"
            available: () => Style.ccTailscale && Tailscale.installed

            Tile {
                icon: "vpn_lock"
                label: "Tailscale"
                detail: Tailscale.shortSummary
                active: Tailscale.busy === "up" || (Tailscale.running && Tailscale.busy !== "down")
                hasPage: true
                onToggled: {
                    if (Tailscale.canControl && Tailscale.switchable)
                        Tailscale.toggle();
                    else
                        ControlState.page = "tailscale";
                }
                onOpenPage: ControlState.page = "tailscale"

                // Fresh while the control center is open, only if the tile is on.
                readonly property bool polls: Style.ccTailscale
                property bool counted: false
                function count(on) {
                    if (on !== counted) {
                        counted = on;
                        Tailscale.use("open", on);
                    }
                }
                onPollsChanged: count(polls)
                Component.onCompleted: count(polls)
                Component.onDestruction: count(false)
            }
        }

        // ---- Hotspot (services/Hotspot.qml) -------------------------------------------
        // Click: on (a second click when it would leave your Wi-Fi network) or
        // off; arrow: its page with the name, the password and a QR code.
        TileSpec {
            tileId: "hotspot"
            label: "Hotspot"
            icon: "wifi_tethering"
            desc: "Share the connection over Wi-Fi (it leaves your Wi-Fi network while on)"

            Tile {
                icon: Hotspot.on || Hotspot.busy === "on" ? "wifi_tethering" : "wifi_tethering_off"
                label: "Hotspot"
                detail: Hotspot.detail
                active: Hotspot.busy === "on" || (Hotspot.on && Hotspot.busy !== "off")
                hasPage: true
                onToggled: Hotspot.tap()
                onOpenPage: ControlState.page = "hotspot"
                Component.onCompleted: Hotspot.use(true)
                Component.onDestruction: Hotspot.use(false)
            }
        }

        // ---- Airplane mode (services/Airplane.qml) ------------------------------------
        TileSpec {
            tileId: "airplane"
            label: "Airplane mode"
            icon: "airplanemode_active"
            desc: "Wi-Fi and Bluetooth off together; off again brings back the ones that were on"

            Tile {
                icon: Airplane.on ? "airplanemode_active" : "airplanemode_inactive"
                label: "Airplane mode"
                detail: Airplane.detail
                active: Airplane.busy === "on" || (Airplane.on && Airplane.busy !== "off")
                onToggled: Airplane.toggle()
            }
        }

        // ---- Name that song (services/SongRec.qml) ------------------------------------
        // Click: listen to what the laptop plays (or the mic: Style.songSource);
        // click again to stop. Right click (or a long press): the other one.
        TileSpec {
            tileId: "song"
            label: "Name that song"
            icon: "music_note"
            desc: "Listens a few seconds and names the song (songrec, Shazam)"

            Tile {
                icon: SongRec.listening ? "graphic_eq" : "music_note"
                label: SongRec.listening ? "Listening…" : "Name that song"
                detail: SongRec.detail
                active: SongRec.listening
                hasSecondary: true
                onToggled: SongRec.toggle("")
                onSecondary: SongRec.toggle(SongRec.otherSource)
            }
        }
    }
}
