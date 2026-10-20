.pragma library

// mango's key binds, turned into the cheat sheet's groups and rows.
// parse(text) takes mango's config with every `source=` file already put in
// its place (CheatSheetState reads them); a line "\u0001file <path>" marks
// where each file starts.
//
//   groups: [{ title, rows: [{ combos: [{ chips: [{ text, icon }], note }],
//                              desc, search }] }]
//
// Groups come from the "# === Apps ===" / "# ---- Keys ----" headers. A
// row's words are the comment right above its bind when that comment is
// about just that bind ("# Leave mango (works even if DMS is dead)" ->
// "Leave mango"); otherwise a plain-words version of what it does.
// Super+1 … Super+9 doing the same thing become one row "Super 1–9", and
// two keys doing exactly the same thing share a row (Super+Enter / Super+T).

// ---- Keys and modifiers -------------------------------------------------------------
const MODS = {
    super: "Super", logo: "Super", win: "Super", mod4: "Super",
    ctrl: "Ctrl", control: "Ctrl",
    alt: "Alt", mod1: "Alt",
    shift: "Shift"
};
const MOD_ORDER = ["Super", "Ctrl", "Alt", "Shift"];

const KEYS = {
    return: "Enter", enter: "Enter", kp_enter: "Enter", space: "Space", tab: "Tab",
    escape: "Esc", backspace: "⌫", delete: "Del", insert: "Ins", home: "Home", end: "End",
    prior: "PgUp", page_up: "PgUp", next: "PgDn", page_down: "PgDn",
    left: "←", right: "→", up: "↑", down: "↓",
    comma: ",", period: ".", slash: "/", backslash: "\\", semicolon: ";", apostrophe: "'",
    grave: "`", minus: "−", equal: "=", plus: "+", bracketleft: "[", bracketright: "]",
    print: "Print",
    xf86audioraisevolume: "Vol +", xf86audiolowervolume: "Vol −", xf86audiomute: "Mute",
    xf86audiomicmute: "Mic mute", xf86audioplay: "Play", xf86audiopause: "Pause",
    xf86audioprev: "Prev", xf86audionext: "Next", xf86audiostop: "Stop",
    xf86monbrightnessup: "Bright +", xf86monbrightnessdown: "Bright −",
    xf86kbdbrightnessup: "Kbd light +", xf86kbdbrightnessdown: "Kbd light −",
    xf86calculator: "Calc", xf86poweroff: "Power", xf86search: "Search", xf86wlan: "Wi-Fi"
};
// Keys that are modifiers themselves: a bind on releasing one is a "tap".
const MOD_KEYS = { super_l: "Super", super_r: "Super", alt_l: "Alt", alt_r: "Alt",
                   control_l: "Ctrl", control_r: "Ctrl", shift_l: "Shift", shift_r: "Shift" };
const ARROWS = { left: "←", right: "→", up: "↑", down: "↓" };

function capital(s) {
    s = String(s ?? "");
    return s.length ? s[0].toUpperCase() + s.slice(1) : s;
}

function keyName(key) {
    const k = String(key).toLowerCase();
    if (KEYS[k] !== undefined)
        return KEYS[k];
    if (k.startsWith("xf86"))                   // XF86TouchpadToggle -> Touchpad Toggle
        return key.slice(4).replace(/([a-z])([A-Z])/g, "$1 $2");
    return key.length === 1 ? key.toUpperCase() : key;
}

// "SUPER+SHIFT" -> [{ text: "Super", icon: … }, { text: "Shift" }], in the usual order.
function modChips(mods) {
    const names = String(mods).split("+").map(m => MODS[m.trim().toLowerCase()]).filter(m => m);
    return MOD_ORDER.filter(m => names.includes(m)).map(chip);
}

function chip(text) {
    return text === "Super" ? { text: "Super", icon: "keyboard_command_key" } : { text: text, icon: "" };
}

// ---- What a bind does, in plain words ------------------------------------------------------
function where(d) {
    return d === "up" ? "above" : d === "down" ? "below" : "on the " + d;
}

const FUNCS = {
    killclient: () => "Close the window",
    togglefullscreen: () => "Fullscreen",
    togglefakefullscreen: () => "Fullscreen inside the tile",
    togglemaximizescreen: () => "Maximize",
    togglefloating: () => "Float or tile the window",
    toggleoverview: () => "Overview of all windows",
    enteroverview: () => "Open the overview",
    leaveoverview: () => "Close the overview",
    reload_config: () => "Reload mango's settings",
    quit: () => "Log out (quit mango)",
    focusstack: a => a[0] === "prev" ? "Previous window" : "Next window",
    focusdir: a => "Focus the window " + where(a[0]),
    exchange_client: a => "Move the window " + a[0],
    focusmon: a => "Focus the " + a[0] + " screen",
    tagmon: a => "Window to the " + a[0] + " screen",
    switch_layout: () => "Next tiling layout",
    setlayout: a => "Tiling layout: " + a[0],
    incgaps: a => Number(a[0]) < 0 ? "Smaller gaps" : "Bigger gaps",
    togglegaps: () => "Gaps on or off",
    view: a => "Go to workspace " + a[0],
    toggleview: a => "Show workspace " + a[0] + " too",
    tag: a => "Move the window to workspace " + a[0],
    tagsilent: a => "Send the window to workspace " + a[0],
    viewtoleft: () => "Previous workspace",
    viewtoright: () => "Next workspace",
    viewtoleft_have_client: () => "Previous workspace with windows",
    viewtoright_have_client: () => "Next workspace with windows",
    viewprev_have_client: () => "Previous workspace with windows",
    viewnext_have_client: () => "Next workspace with windows",
    moveresize: a => a[0] === "curresize" ? "Resize the window" : "Move the window",
    setmfact: a => Number(a[0]) < 0 ? "Smaller main area" : "Bigger main area",
    incnmaster: a => Number(a[0]) < 0 ? "Fewer main windows" : "More main windows",
    zoom: () => "Make it the main window",
    minimized: () => "Minimize",
    restore_minimized: () => "Bring back minimized windows",
    toggle_scratchpad: () => "Scratchpad",
    toggleglobal: () => "Show on every workspace",
    toggleoverlay: () => "Keep above other windows",
    switch_keyboard_layout: () => "Next keyboard layout",
    switch_proportion_preset: () => "Next window width",
    scroller_stack: a => "Stack with the window " + where(a[0]),
    chvt: a => "Text console " + a[0],
    spawn: a => spawnName(a.join(",")),
    spawn_shell: a => spawnName(a.join(","))
};

// `mine <what>` (~/.local/bin/mine): my shell's own things.
const MINE = {
    "launcher": "Launcher",
    "clipboard": "Clipboard history",
    "settings": "Settings",
    "control-center": "Control center",
    "wallpaper": "Wallpaper picker",
    "session": "Power menu",
    "cheatsheet": "These shortcuts",
    "screenshot region": "Screenshot of an area",
    "screenshot window": "Screenshot of a window",
    "screenshot screen": "Screenshot of the whole screen",
    "switcher next": "Switch windows",
    "switcher previous": "Switch windows, backwards",
    "key volume-up": "Volume up",
    "key volume-down": "Volume down",
    "key volume-mute": "Mute the sound",
    "key mic-mute": "Mute the microphone",
    "key play": "Play or pause",
    "key previous": "Previous song",
    "key next": "Next song",
    "key brightness-up": "Brighter",
    "key brightness-down": "Dimmer",
    "record": "Screen recording",
    "color-picker": "Pick a color from the screen",
    "colorpicker": "Pick a color from the screen",
    "nightlight": "Night light",
    "restart": "Restart the shell"
};

const APPS = {
    foot: "Terminal", kitty: "Terminal", alacritty: "Terminal", ghostty: "Terminal", wezterm: "Terminal",
    nautilus: "Files", thunar: "Files", dolphin: "Files", nemo: "Files",
    zen: "Zen browser", firefox: "Firefox", "brave-nightly": "Brave", "brave-browser": "Brave", chromium: "Chromium",
    "qs-lock": "Lock the screen", hyprlock: "Lock the screen", swaylock: "Lock the screen",
    pavucontrol: "Sound settings", btop: "System monitor", htop: "System monitor",
    hyprpicker: "Pick a color from the screen", "gnome-calculator": "Calculator"
};

function spawnName(cmd) {
    let t = String(cmd).trim().split(/\s+/);
    // env A=1 B=2 app …  /  xdg-terminal-exec app …
    while (t.length > 1 && (t[0] === "env" || /^[A-Z_]+=/.test(t[0]) || t[0] === "xdg-terminal-exec"))
        t = t.slice(1);
    const base = t[0].split("/").pop();
    if (base === "mine")
        return MINE[t.slice(1).join(" ")] ?? MINE[t[1]] ?? capital((t[1] ?? "").replace(/[-_]/g, " "));
    if (base === "mango-focus-or-launch" && t[1])     // jump to it if open, else start it
        return capital(t[1]);
    if (base === "flatpak" && t[1] === "run" && t[2])
        return capital(t[2].split(".").pop());
    if (APPS[base] !== undefined)
        return APPS[base];
    return capital(base.replace(/[-_]/g, " "));
}

function describe(func, args) {
    const f = FUNCS[func];
    if (f)
        return f(args);
    return capital(func.replace(/_/g, " ")) + (args.length && args[0] !== "" ? " " + args.join(" ") : "");
}

// The comment above a bind, cut to a short label:
//   "Super+N: go to workspace N"                   -> "Go to workspace N"
//   "Clipboard history: my shell's, or Noctalia's" -> "Clipboard history"
//   "Leave mango (works even if DMS is dead)"      -> "Leave mango"
function fromComment(lines) {
    let t = lines.join(" ").replace(/\s+/g, " ").trim();
    const colon = t.indexOf(":");
    if (colon > 0) {
        const before = t.slice(0, colon);
        // "Super+N: …" / "3 fingers left/right: …" name the keys first.
        t = /super|\balt\b|shift|ctrl|finger|\+|print/i.test(before) ? t.slice(colon + 1) : before;
    }
    t = t.replace(/\([^)]*\)/g, "").split(/;|\(|\.\s|\.$/)[0];
    t = t.replace(/\s+/g, " ").trim().replace(/[,.:]+$/, "");
    if (t === "" || t.length > 60)
        return "";
    return capital(t);
}

// ---- Reading ------------------------------------------------------------------------------
function groupTitle(t) {
    return t.replace(/\s*\([^)]*\)/g, "").replace(/\s+\d+\s*-\s*\d+$/, "").trim();
}

function parse(text) {
    const lines = String(text ?? "").split("\n");
    const binds = [];
    let file = "";
    let group = "Other";
    let comment = [];       // comment lines right above
    let run = null;         // { lines, count }: the binds right under one comment

    for (const raw of lines) {
        if (raw.charCodeAt(0) === 1) {          // a file starts (or goes on after a source=)
            file = raw.slice(6);
            comment = [];
            run = null;
            continue;
        }
        const line = raw.trim();
        const header = line.match(/^#\s*(?:={3,}|-{3,})\s*(.+?)\s*(?:={3,}|-{3,})?\s*$/);
        if (header && /[A-Za-z]/.test(header[1])) {
            group = groupTitle(header[1]);
            // The shell's own keys (shell-mine.conf's "Keys").
            if (group === "Keys" && /shell/.test(file.split("/").pop()))
                group = "Shell";
            comment = [];
            run = null;
            continue;
        }
        if (line.startsWith("#")) {
            if (run)
                comment = [];
            run = null;
            comment.push(line.replace(/^#+\s?/, ""));
            continue;
        }
        const m = line.match(/^(bind[a-z]*|mousebind|gesturebind|axisbind)\s*=\s*(.*)$/);
        if (!m) {
            comment = [];
            run = null;
            continue;
        }
        if (comment.length > 0) {
            run = { lines: comment, count: 0 };
            comment = [];
        }
        // An inline " #" ends the line for mango too.
        const parts = m[2].replace(/\s+#.*$/, "").split(",").map(s => s.trim());
        const b = { kind: m[1], group: group, run: run };
        if (run)
            run.count++;
        if (m[1] === "gesturebind") {           // mods, direction, fingers, func, args
            b.chips = modChips(parts[0]).concat([
                { text: parts[2] + " fingers", icon: "swipe" },
                { text: ARROWS[parts[1].toLowerCase()] ?? parts[1], icon: "" }
            ]);
            b.func = parts[3] ?? "";
            b.args = parts.slice(4);
        } else if (m[1] === "mousebind") {      // mods, button, func, args
            const button = { btn_left: "Left", btn_right: "Right", btn_middle: "Middle" }[parts[1]] ?? parts[1];
            b.func = parts[2] ?? "";
            b.args = parts.slice(3);
            b.chips = modChips(parts[0]).concat([{ text: button + (b.func === "moveresize" ? " drag" : " click"), icon: "mouse" }]);
        } else if (m[1] === "axisbind") {       // mods, direction, func, args
            b.chips = modChips(parts[0]).concat([{ text: "Scroll " + (ARROWS[parts[1].toLowerCase()] ?? parts[1]), icon: "mouse" }]);
            b.func = parts[2] ?? "";
            b.args = parts.slice(3);
        } else {                                // bind, bindl, bindr…: mods, key, func, args
            const mods = modChips(parts[0]);
            const key = parts[1] ?? "";
            const flags = m[1].slice(4);
            const modKey = MOD_KEYS[key.toLowerCase()];
            if (modKey) {
                // A modifier on its own (bindr=SUPER,Super_L): a tap.
                b.chips = mods.some(c => c.text === modKey) ? mods : mods.concat([chip(modKey)]);
                if (flags.includes("r"))
                    b.note = "tap";
            } else {
                b.chips = mods.concat([chip(keyName(key))]);
            }
            b.key = key;
            b.mods = parts[0];
            b.func = parts[2] ?? "";
            b.args = parts.slice(3);
        }
        b.action = b.func + "," + b.args.join(",");
        // My shell's media keys and screenshots get their own groups.
        const cmd = b.func.startsWith("spawn") ? b.args.join(",") : "";
        if (/\bmine key\b/.test(cmd))
            b.group = "Media & brightness";
        else if (/\bmine screenshot\b/.test(cmd))
            b.group = "Screenshots";
        binds.push(b);
    }
    return build(binds);
}

// ---- Rows ------------------------------------------------------------------------------------
function build(binds) {
    const order = [];
    const byGroup = {};
    for (const b of binds) {
        if (!byGroup[b.group]) {
            byGroup[b.group] = [];
            order.push(b.group);
        }
        byGroup[b.group].push(b);
    }
    return order.map(title => ({ title: title, rows: rowsOf(byGroup[title]) }));
}

function rowsOf(binds) {
    // 1. Super+1 … Super+9 doing view 1 … view 9: one row.
    const items = [];
    for (let i = 0; i < binds.length; i++) {
        const b = binds[i];
        let j = i;
        const digit = k => /^[0-9]$/.test(k ?? "");
        if (digit(b.key) && b.args[0] === b.key) {
            while (j + 1 < binds.length) {
                const n = binds[j + 1];
                if (n.mods === b.mods && n.func === b.func && n.kind === b.kind && digit(n.key)
                        && Number(n.key) === Number(binds[j].key) + 1 && n.args[0] === n.key)
                    j++;
                else
                    break;
            }
        }
        if (j - i >= 2) {
            const range = b.key + "–" + binds[j].key;
            const chips = b.chips.slice(0, -1).concat([{ text: range, icon: "" }]);
            items.push({ binds: binds.slice(i, j + 1), combos: [{ chips: chips, note: "" }],
                         range: range, action: "range:" + b.func + ":" + b.mods });
            i = j;
        } else {
            items.push({ binds: [b], combos: [{ chips: b.chips, note: b.note ?? "" }], range: "", action: b.action });
        }
    }

    // 2. Different keys doing exactly the same thing share a row.
    const rows = [];
    const byAction = {};
    for (const it of items) {
        const same = byAction[it.action];
        if (same && it.range === "") {
            same.binds = same.binds.concat(it.binds);
            same.combos = same.combos.concat(it.combos);
        } else {
            const row = { binds: it.binds, combos: it.combos, range: it.range, action: it.action };
            byAction[it.action] = row;
            rows.push(row);
        }
    }

    return rows.map(r => {
        const b = r.binds[0];
        // Super+← / Super+H -> Super ← / H: later keys with the same
        // modifiers show only their last key.
        const first = r.combos[0].chips;
        const prefix = first.slice(0, -1).map(k => k.text).join("+");
        const combos = r.combos.map((c, i) => i > 0 && c.chips.length === first.length && c.note === r.combos[0].note
                                    && c.chips.slice(0, -1).map(k => k.text).join("+") === prefix
                                    ? { chips: c.chips.slice(-1), note: c.note } : c);
        const plain = describe(b.func, r.range !== "" ? [r.range] : b.args);
        let desc = "";
        // The comment is about this row only: every bind under it is here.
        if (b.run && r.binds.every(x => x.run === b.run) && b.run.count === r.binds.length) {
            desc = fromComment(b.run.lines);
            if (r.range !== "")
                desc = desc.replace(/\bN\b/g, r.range);
            // "Lock" from the comment, "Lock the screen" from what it runs: the longer one.
            if (desc !== "" && plain.toLowerCase().startsWith(desc.toLowerCase()))
                desc = plain;
        }
        if (desc === "")
            desc = plain;
        const keys = r.combos.map(c => c.chips.map(k => k.text).join(" ") + (c.note ? " " + c.note : "")).join(" ");
        return { combos: combos, desc: desc, search: (desc + " " + keys).toLowerCase() };
    });
}

// Groups with only the rows matching `query` (every word somewhere in the
// row's words or keys, or in the group's title).
function filter(groups, query) {
    const words = String(query ?? "").toLowerCase().split(/\s+/).filter(w => w);
    if (words.length === 0)
        return groups;
    const out = [];
    for (const g of groups) {
        const title = g.title.toLowerCase();
        const rows = g.rows.filter(r => words.every(w => r.search.includes(w) || title.includes(w)));
        if (rows.length > 0)
            out.push({ title: g.title, rows: rows });
    }
    return out;
}

// ---- Keys by what they do ----------------------------------------------------------------
// For the bar's tips: { "mine:session": "Super+X", "func:switch_layout":
// "Super+Alt+J", "func:view,3": "Super+3", "mine:launcher": "Super" … },
// from the same expanded config as parse(). A shell command counts by what
// follows "mine " (`mine screenshot region` -> "mine:screenshot region"),
// anything else by mango's function. The first bind for a thing wins; a
// modifier tapped on its own (bindr=SUPER,Super_L) is just its name.
function shortcuts(text) {
    const out = {};
    for (const raw of String(text ?? "").split("\n")) {
        const m = raw.trim().match(/^bind[a-z]*\s*=\s*(.*)$/);
        if (!m)
            continue;
        const parts = m[1].replace(/\s+#.*$/, "").split(",").map(s => s.trim());
        const func = parts[2] ?? "";
        const args = parts.slice(3).join(",");
        let id = "func:" + func;
        if (func.startsWith("spawn")) {
            const mine = args.match(/(?:^|[\/\s])mine\s+(.+)$/);
            if (!mine)
                continue;
            id = "mine:" + mine[1].trim();
        }
        const key = parts[1] ?? "";
        const mods = modChips(parts[0]).map(c => c.text);
        const modKey = MOD_KEYS[key.toLowerCase()];
        const names = modKey ? (mods.includes(modKey) ? mods : mods.concat([modKey])) : mods.concat([keyName(key)]);
        // Also with its arguments: "func:view,3" -> "Super+3".
        for (const k of id.startsWith("func:") && args !== "" ? [id, id + "," + args] : [id])
            if (out[k] === undefined)
                out[k] = names.join("+");
    }
    return out;
}
