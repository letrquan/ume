pragma Singleton
import QtQuick
import Quickshell

// Everything that can go on the bar, and the edits the Settings window's
// "Bar items" page makes. What each island holds is Style.barLeft /
// barCenter / barRight (lists of the names below); BarContent draws them.
// Each item is on the bar at most once, except the divider.
Singleton {
    id: root

    readonly property var islands: [
        { key: "barLeft", title: "Left island" },
        { key: "barCenter", title: "Middle island" },
        { key: "barRight", title: "Right island" }
    ]

    readonly property var all: [
        { name: "launcher", label: "App launcher", icon: "apps", desc: "Opens the launcher (or tap Super)" },
        { name: "workspaces", label: "Workspaces", icon: "workspaces", desc: "Click one to go there, scroll to move" },
        { name: "layout", label: "Tiling layout", icon: "auto_awesome_mosaic", desc: "Click: the next layout (Super+Alt+J)" },
        { name: "window", label: "Window title", icon: "tab", desc: "The focused window's icon and title" },
        { name: "clock", label: "Clock", icon: "schedule", desc: "Click: calendar and weather" },
        { name: "media", label: "Now playing", icon: "music_note", desc: "Song and controls, while something plays" },
        { name: "tray", label: "Tray icons", icon: "widgets", desc: "Discord, Steam, …" },
        { name: "updates", label: "Updates", icon: "deployed_code_update", desc: "How many packages wait (repos, AUR, Flatpak), while some do; click: the updates panel (or a terminal), right click: check now" },
        { name: "status", label: "Status", icon: "wifi", desc: "Wi-Fi, volume and battery as one button: click for the control center, scroll for volume (the battery's number shows while low or charging)" },
        { name: "network", label: "Network", icon: "wifi", desc: "Wi-Fi or wired" },
        { name: "bluetooth", label: "Bluetooth", icon: "bluetooth", desc: "" },
        { name: "volume", label: "Volume", icon: "volume_up", desc: "Click: volume popup, scroll to change" },
        { name: "battery", label: "Battery", icon: "battery_full", desc: "" },
        { name: "notifications", label: "Notifications", icon: "notifications", desc: "The bell; right click: Silent" },
        { name: "controls", label: "Control center", icon: "tune", desc: "" },
        { name: "power", label: "Power menu", icon: "power_settings_new", desc: "" },
        { name: "recording", label: "Recording", icon: "screen_record", desc: "A red dot and the time while the screen is recorded; click to stop" },
        { name: "focus", label: "Focus timer", icon: "timer", desc: "Click: start or pause, right click: stop, scroll: longer or shorter" },
        { name: "devices", label: "Device batteries", icon: "headphones", desc: "Headphones, mouse, game pad…: their battery, while connected" },
        { name: "agents", label: "Claude Code", icon: "smart_toy", desc: "Sessions working (◐) and done or waiting for you (✳), while there are any; click: the one waiting longest" },
        { name: "tailscale", label: "Tailscale", icon: "vpn_lock", desc: "Dim while it's off; hover: devices online; click: its control center page" },
        { name: "phone", label: "Phone", icon: "smartphone", desc: "Your phone's battery (KDE Connect), while one is paired; click: the Phone page" },
        { name: "keyboard", label: "On-screen keyboard", icon: "keyboard", desc: "Tap: the keyboard on the screen, for touch (it also comes up in tablet mode)" },
        { name: "privacy", label: "Privacy dots", icon: "privacy_tip", desc: "Orange: an app records the mic (click: mute), green: the camera is on, purple: the screen is shared; hover: which apps" },
        { name: "cpu", label: "CPU", icon: "memory", desc: "How busy the processor is" },
        { name: "memory", label: "Memory", icon: "memory_alt", desc: "RAM in use" },
        { name: "temperature", label: "Temperature", icon: "device_thermostat", desc: "The CPU's" },
        { name: "netspeed", label: "Network speed", icon: "arrow_downward", desc: "Download (hover: upload)" },
        { name: "disk", label: "Disk", icon: "hard_drive", desc: "How full / is" },
        { name: "drives", label: "USB drives", icon: "usb", desc: "While a USB drive or SD card is plugged in; click: its size and free space, Open and Eject" },
        // Screen time and AI usage (services/ScreenTime.qml, services/AiUsage.qml).
        { name: "screentime", label: "Screen time", icon: "hourglass_bottom", desc: "Today's time on the screen; click: per app, the last 7 days and break reminders" },
        { name: "aiusage", label: "AI usage", icon: "data_usage", desc: "Claude's 5-hour and weekly limits and Codex's, as rings, while signed in; click: details and reset times" },
        // The timer (services/Timers.qml).
        { name: "timers", label: "Timer", icon: "hourglass_top", desc: "The time left while a timer runs (or a bell while one rings); click: pause or stop, right click: cancel" },
        { name: "divider", label: "Divider", icon: "more_vert", desc: "A thin line between groups" }
    ]

    function info(name) {
        return all.find(i => i.name === name) ?? { name: name, label: name, icon: "help", desc: "Unknown item" };
    }

    function list(key) {
        return Style[key] ?? [];
    }

    // Not on the bar right now (the divider always can be added).
    readonly property var unused: {
        const used = Style.barLeft.concat(Style.barCenter, Style.barRight);
        return all.filter(i => i.name === "divider" || !used.includes(i.name));
    }

    function save(key, items) {
        Settings.set(key, items);
    }

    // One step left (-1) or right (+1) inside its island.
    function move(key, index, by) {
        const items = list(key).slice();
        const to = index + by;
        if (to < 0 || to >= items.length)
            return;
        [items[index], items[to]] = [items[to], items[index]];
        save(key, items);
    }

    // To the next island over (-1 = left, +1 = right): it lands on the
    // side nearest to where it came from.
    function moveIsland(key, index, by) {
        const keys = islands.map(i => i.key);
        const target = keys[keys.indexOf(key) + by];
        if (target === undefined)
            return;
        const from = list(key).slice();
        const name = from.splice(index, 1)[0];
        const to = list(target).slice();
        if (by > 0)
            to.unshift(name);
        else
            to.push(name);
        save(key, from);
        save(target, to);
    }

    function remove(key, index) {
        const items = list(key).slice();
        items.splice(index, 1);
        save(key, items);
    }

    function add(key, name) {
        if (name !== "divider" && !unused.some(i => i.name === name))
            return;     // already on the bar
        save(key, list(key).concat([name]));
    }
}
