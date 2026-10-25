.pragma library

// Small pure helpers for sharing a Wi-Fi network as a QR code (the Wi-Fi
// page's Share and the hotspot page). No I/O here, so they are easy to
// test on their own (node: the functions are plain JS).

// nmcli -t -e no -f a,b,c ... : one "name:value" line per field. The value
// is everything after the FIRST colon (names have none; values may), and
// only the line break is taken off: a password can start or end with a
// space, so nothing is trimmed.
function fields(text) {
    const out = {};
    for (const line of String(text ?? "").split("\n")) {
        const at = line.indexOf(":");
        if (at <= 0)
            continue;
        out[line.substring(0, at)] = line.substring(at + 1).replace(/\r$/, "");
    }
    return out;
}

// nmcli -t -e no -f A,B,C <list>: lines of colon separated columns. Only
// the LAST column may hold colons (a connection's name), so it gets the rest.
function rows(text, count) {
    const out = [];
    for (const line of String(text ?? "").split("\n")) {
        if (line === "")
            continue;
        const parts = line.split(":");
        if (parts.length < count)
            continue;
        out.push(parts.slice(0, count - 1).concat([parts.slice(count - 1).join(":")]));
    }
    return out;
}

// The QR text format phones read (ZXing's "WIFI:" scheme, which Android
// and iOS cameras both join from): \ ; , : and " are escaped with a
// backslash (the backslash first).
function escape(s) {
    return String(s ?? "").replace(/[\\;,:"]/g, c => "\\" + c);
}

// What kind of network, from NetworkManager's key-mgmt:
//   "WPA"     wpa-psk (WPA2) and sae (WPA3): phones take T:WPA for both
//   "WEP"     none with a WEP key
//   "nopass"  open, or owe (enhanced open: no password either)
//   ""        802.1X (wpa-eap, ieee8021x): a user name and more, no code can carry that
function kind(keyMgmt, wepKey) {
    const k = String(keyMgmt ?? "").trim();
    if (k === "" || k === "owe")
        return "nopass";
    if (k === "wpa-psk" || k === "sae")
        return "WPA";
    if (k === "none")
        return wepKey ? "WEP" : "nopass";
    return "";
}

// WIFI:T:WPA;S:<name>;P:<password>;H:true;;  ("" when it can't be shared)
function wifiText(ssid, type, password, hidden) {
    if (type === "" || ssid === "")
        return "";
    let t = "WIFI:";
    if (type !== "nopass")
        t += "T:" + type + ";";
    t += "S:" + escape(ssid) + ";";
    if (type !== "nopass")
        t += "P:" + escape(password) + ";";
    if (hidden)
        t += "H:true;";
    return t + ";";
}

// qrencode -t ASCII -m 0: a line per row of the code, two characters per
// square, "##" for a dark one. Gives rows of booleans ([] if it isn't one).
function parseAscii(text) {
    const lines = String(text ?? "").split("\n").filter(l => l.length > 0);
    const out = [];
    for (const line of lines) {
        const row = [];
        for (let i = 0; i < line.length; i += 2)
            row.push(line.charAt(i) === "#");
        out.push(row);
    }
    // A code is square: as many rows as squares in a row.
    const n = out.length;
    if (n < 21 || out.some(r => r.length < n))
        return [];
    return out.map(r => r.slice(0, n));
}

// The dark squares as runs along each row: [{ x, y, w }], fewer pieces
// to draw than one per square.
function runs(modules) {
    const out = [];
    for (let y = 0; y < modules.length; y++) {
        const row = modules[y];
        let x = 0;
        while (x < row.length) {
            if (!row[x]) {
                x++;
                continue;
            }
            const start = x;
            while (x < row.length && row[x])
                x++;
            out.push({ x: start, y: y, w: x - start });
        }
    }
    return out;
}
