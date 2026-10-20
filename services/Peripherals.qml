pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs.common

// The batteries of what's connected to the laptop: Bluetooth headphones,
// a wireless mouse or keyboard, a game pad… (not the laptop's own).
// UPower knows most of them (also USB receivers); Bluetooth adds headsets
// that only tell BlueZ. One entry per device:
//   [{ key, name, glyph (Material Symbols), percent 0-100, charging }]
// Below Style.deviceBatteryWarn % a notification says so, once (again only
// after it has been charged above that).
//
// Tests: MINE_PERIPHERALS_FAKE = a JSON list of entries instead of the real
// ones; MINE_PERIPHERALS_DRYRUN=1 only prints the notification.
Singleton {
    id: root

    readonly property string fake: Quickshell.env("MINE_PERIPHERALS_FAKE") ?? ""
    readonly property bool dryRun: Quickshell.env("MINE_PERIPHERALS_DRYRUN") === "1"
    // Tests can change the fake list while running.
    property var fakeList: {
        try {
            return root.fake !== "" ? JSON.parse(root.fake) : null;
        } catch (e) {
            return null;
        }
    }

    // A Material Symbols glyph for a UPower device type or a BlueZ icon name.
    function glyphFor(kind) {
        const k = String(kind).toLowerCase();
        if (k.includes("headset") || k.includes("headphone") || k.includes("audio-headphones"))
            return "headphones";
        if (k.includes("speaker") || k.includes("audio"))
            return "speaker";
        if (k.includes("mouse") || k.includes("touchpad"))
            return "mouse";
        if (k.includes("keyboard"))
            return "keyboard";
        if (k.includes("gaming") || k.includes("joystick"))
            return "sports_esports";
        if (k.includes("phone"))
            return "smartphone";
        if (k.includes("pen") || k.includes("tablet"))
            return "stylus";
        if (k.includes("watch") || k.includes("wearable"))
            return "watch";
        return "battery_horiz_050";
    }

    // "AA:BB:CC:DD:EE:FF" or ".../dev_AA_BB_CC_DD_EE_FF" -> "aabbccddeeff".
    function addressKey(text) {
        const m = String(text ?? "").match(/([0-9A-Fa-f]{2}[:_]){5}[0-9A-Fa-f]{2}/);
        return m ? m[0].replace(/[:_]/g, "").toLowerCase() : "";
    }

    readonly property var devices: {
        if (fakeList)
            return fakeList;
        const out = [];
        const seen = {};
        // UPower: present devices that aren't power supplies (the laptop's
        // battery, chargers) and report a level.
        for (const d of UPower.devices.values) {
            if (!d.isPresent || d.powerSupply || d.isLaptopBattery || d.type === UPowerDeviceType.LinePower)
                continue;
            const key = addressKey(d.nativePath) || d.nativePath;
            seen[key] = true;
            out.push({
                key: key,
                name: d.model || UPowerDeviceType.toString(d.type),
                glyph: glyphFor(UPowerDeviceType.toString(d.type)),
                percent: Math.round(d.percentage * 100),
                charging: d.state === UPowerDeviceState.Charging
            });
        }
        // Bluetooth: connected ones with a battery UPower didn't list.
        for (const d of Bluetooth.devices.values) {
            if (!d.connected || !d.batteryAvailable)
                continue;
            const key = addressKey(d.address);
            if (seen[key])
                continue;
            out.push({
                key: key,
                name: d.name || d.deviceName || d.address,
                glyph: glyphFor(d.icon),
                percent: Math.round(d.battery * 100),
                charging: false
            });
        }
        return out;
    }

    // The battery of one Bluetooth device as text ("80%"), "" if unknown.
    function levelOf(btDevice) {
        if (!btDevice)
            return "";
        if (btDevice.batteryAvailable)
            return Math.round(btDevice.battery * 100) + "%";
        const key = addressKey(btDevice.address);
        const d = devices.find(x => x.key === key);
        return d ? d.percent + "%" : "";
    }

    // ---- Low battery ---------------------------------------------------------------------
    // Keys already told about (until charged above the line again).
    property var warned: ({})
    onDevicesChanged: check()
    function check() {
        const line = Style.deviceBatteryWarn;
        if (line <= 0)
            return;
        const next = {};
        for (const d of devices) {
            const low = d.percent > 0 && d.percent < line && !d.charging;
            if (low && !warned[d.key])
                notify(d);
            // Still low: stays told. Charged a bit above the line: may warn again.
            if (low || (warned[d.key] && d.percent < line + 5 && !d.charging))
                next[d.key] = true;
        }
        warned = next;
    }

    function notify(d) {
        // "--": the name is the device's own (a Bluetooth name can start with "-").
        const cmd = ["notify-send", "-a", "Devices", "-i", "battery-caution", "-h", "string:category:device",
                     "--", d.name + " battery low", d.percent + "% left"];
        if (dryRun)
            console.log("devices (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }
}
