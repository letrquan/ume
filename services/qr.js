.pragma library

// Reading what zbarimg found (scripts/qr-scan.sh, `zbarimg --xml`) and
// what kind of thing each code holds: a web link, a Wi-Fi network, or
// just text. For services/Screenshot.qml's QR scan; no Qt in here, so a
// plain JS test can load it too.

// zbarimg --xml → [{ type: "QR-Code", data: "…" }], in the order found.
// The data sits in CDATA; zbar writes it as base64 (format='base64') when
// it isn't plain text or holds "]]>".
function parseZbarXml(xml) {
    const out = [];
    const re = /<symbol\b([^>]*)>[\s\S]*?<data\b([^>]*)><!\[CDATA\[([\s\S]*?)\]\]><\/data>[\s\S]*?<\/symbol>/g;
    let m;
    while ((m = re.exec(String(xml ?? ""))) !== null) {
        const type = (m[1].match(/type='([^']*)'/) ?? [])[1] ?? "";
        let data = m[3];
        if (/format='base64'/.test(m[2]))
            data = fromBase64(data);
        out.push({ type: type, data: data });
    }
    return out;
}

// Base64 → text (UTF-8). Without Qt.atob (a plain JS test has none) it's
// decoded by hand.
function fromBase64(b64) {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const clean = String(b64).replace(/[^A-Za-z0-9+/]/g, "");
    const bytes = [];
    let bits = 0, value = 0;
    for (const c of clean) {
        value = (value << 6) | chars.indexOf(c);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            bytes.push((value >> bits) & 255);
        }
    }
    return utf8(bytes);
}

function utf8(bytes) {
    let s = "";
    for (let i = 0; i < bytes.length; i++) {
        const b = bytes[i];
        let cp = b, extra = 0;
        if (b >= 0xf0) { cp = b & 7; extra = 3; }
        else if (b >= 0xe0) { cp = b & 15; extra = 2; }
        else if (b >= 0xc0) { cp = b & 31; extra = 1; }
        for (let k = 0; k < extra && i + 1 < bytes.length; k++)
            cp = (cp << 6) | (bytes[++i] & 63);
        s += String.fromCodePoint(cp);
    }
    return s;
}

// "QR-Code" → "QR code", "EAN-13" → "EAN-13 barcode".
function typeName(type) {
    if (/^QR/i.test(type))
        return "QR code";
    if (/^SQ/i.test(type))
        return "SQ code";
    return (type || "Bar") + " barcode";
}

// A web link Open may hand to the browser: http(s) only, one line, no
// spaces, and none of the invisible characters that make text read
// differently from what it is (right-to-left overrides, zero-width ones,
// controls): "https://a.example/\u202Eexe.gpj" shows as "...gpj.exe".
// javascript:, file:, intent: and the rest stay text.
function isWebLink(text) {
    const t = String(text ?? "").trim();
    return /^https?:\/\/[^\s<>"]+$/i.test(t)
        && !/[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]/.test(t);
}

// WIFI:T:WPA;S:My\;Cafe;P:secret;H:false;; → { ssid, password, security,
// hidden }, or null when it isn't one. Backslash escapes \; \, \: \\ \".
function parseWifi(text) {
    const t = String(text ?? "").trim();
    if (!/^WIFI:/i.test(t))
        return null;
    const fields = {};
    let key = "", value = "", inValue = false;
    for (let i = 5; i < t.length; i++) {
        const c = t[i];
        if (c === "\\" && i + 1 < t.length) {
            i++;
            if (inValue)
                value += t[i];
            else
                key += t[i];
        } else if (!inValue && c === ":") {
            inValue = true;
        } else if (c === ";") {
            if (key !== "")
                fields[key.toUpperCase()] = value;
            key = "";
            value = "";
            inValue = false;
        } else if (inValue) {
            value += c;
        } else {
            key += c;
        }
    }
    if (key !== "")
        fields[key.toUpperCase()] = value;
    if (!fields.S)
        return null;
    const security = (fields.T ?? "").toUpperCase();
    return {
        ssid: fields.S,
        password: security === "NOPASS" ? "" : (fields.P ?? ""),
        security: security === "" || security === "NOPASS" ? (fields.P ? "WPA" : "") : security,
        hidden: /^true$/i.test(fields.H ?? "")
    };
}

// One code → { kind: "url" | "wifi" | "text", … }.
function classify(code) {
    const data = String(code?.data ?? "");
    const wifi = parseWifi(data);
    if (wifi)
        return Object.assign({ kind: "wifi", type: code.type }, wifi);
    if (isWebLink(data))
        return { kind: "url", type: code.type, url: data.trim() };
    return { kind: "text", type: code.type, text: data };
}
