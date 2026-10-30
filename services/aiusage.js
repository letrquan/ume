// Reading Claude's and Codex's usage answers (services/AiUsage.qml), as
// plain functions so the tests can feed them the captured answers.
//
// Only numbers, reset times and a few names are kept: never the account's
// ids or email (Codex sends them along), never a token.
.pragma library

// "2026-10-26T04:39:59.977154+00:00" -> ms. By hand: QML's Date.parse doesn't
// take six decimals. NaN when it isn't such a time.
function isoTime(s) {
    if (typeof s !== "string")
        return NaN;
    const m = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|[+-]\d{2}:?\d{2})?$/.exec(s.trim());
    if (!m)
        return NaN;
    const ms = m[7] ? Math.floor(Number("0." + m[7]) * 1000) : 0;
    let t = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6] ?? 0), ms);
    const zone = m[8];
    if (zone && zone !== "Z") {
        const sign = zone[0] === "-" ? -1 : 1;
        const digits = zone.substring(1).replace(":", "");
        t -= sign * (Number(digits.substring(0, 2)) * 60 + Number(digits.substring(2, 4))) * 60000;
    }
    return t;
}

function percentOf(v) {
    const n = Number(v);
    return v === null || v === undefined || !isFinite(n) ? NaN : Math.max(0, Math.min(999, n));
}

// A name from the answer, as plain short text.
function label(s, fallback) {
    if (typeof s !== "string")
        return fallback;
    const t = s.replace(/[\u0000-\u001f\u007f<>]/g, "").trim();
    return t === "" ? fallback : t.substring(0, 40);
}

// "normal" | "warn" | "critical": the answer's own word when it gives one,
// else from the percent (warnAt / criticalAt).
function severityOf(percent, given, warnAt, criticalAt) {
    const g = typeof given === "string" ? given.toLowerCase() : "";
    if (/crit|exceed|reached|block/.test(g))
        return "critical";
    if (/warn|high|near|approach/.test(g))
        return "warn";
    if (/normal|ok|low|fine/.test(g))
        return "normal";
    if (!isFinite(percent))
        return "normal";
    return percent >= criticalAt ? "critical" : percent >= warnAt ? "warn" : "normal";
}

function windowOf(name, percent, resetsAt, given, warnAt, criticalAt) {
    return {
        label: name,
        percent: percent,
        resetsAt: isFinite(resetsAt) ? resetsAt : 0,
        severity: severityOf(percent, given, warnAt, criticalAt)
    };
}

// Claude (api.anthropic.com/api/oauth/usage): the `limits` list when there
// is one (session / weekly_all / weekly_scoped), else the older five_hour /
// seven_day; the 7-day breakdown rows. Everything else in it is ignored
// (its keys change). null when there's nothing usable.
function parseClaude(o, warnAt, criticalAt) {
    if (!o || typeof o !== "object")
        return null;
    let session = null, weekly = null;
    const models = [];
    if (Array.isArray(o.limits)) {
        for (const l of o.limits) {
            const p = percentOf(l?.percent);
            if (!l || !isFinite(p))
                continue;
            const at = isoTime(l.resets_at);
            if (l.kind === "session" && !session)
                session = windowOf("5-hour", p, at, l.severity, warnAt, criticalAt);
            else if (l.kind === "weekly_all" && !weekly)
                weekly = windowOf("Weekly", p, at, l.severity, warnAt, criticalAt);
            else if (l.kind === "weekly_scoped" && models.length < 6)
                models.push(windowOf(label(l.scope?.model?.display_name, "A model"), p, at, l.severity, warnAt, criticalAt));
        }
    }
    if (!session && o.five_hour && isFinite(percentOf(o.five_hour.utilization)))
        session = windowOf("5-hour", percentOf(o.five_hour.utilization), isoTime(o.five_hour.resets_at), "", warnAt, criticalAt);
    if (!weekly && o.seven_day && isFinite(percentOf(o.seven_day.utilization)))
        weekly = windowOf("Weekly", percentOf(o.seven_day.utilization), isoTime(o.seven_day.resets_at), "", warnAt, criticalAt);
    if (!session && !weekly && models.length === 0)
        return null;
    const rows = Array.isArray(o.seven_day_breakdown?.rows) ? o.seven_day_breakdown.rows : [];
    const breakdown = rows.map(r => ({ label: label(r?.display_name, ""), percent: percentOf(r?.percent) }))
                          .filter(r => r.label !== "" && isFinite(r.percent)).slice(0, 8);
    return { session: session, weekly: weekly, models: models, breakdown: breakdown };
}

// A window's length as a name: 5-hour, Weekly, 30-day…
function windowName(seconds) {
    const s = Number(seconds);
    if (!isFinite(s) || s <= 0)
        return "Limit";
    if (Math.abs(s - 604800) < 3600)
        return "Weekly";
    if (s < 86400)
        return Math.round(s / 3600) + "-hour";
    return Math.round(s / 86400) + "-day";
}

// Codex (chatgpt.com/backend-api/wham/usage): rate_limit's primary and
// secondary windows (the second may be null) and the plan. The ids and the
// email in the answer are never read.
function parseCodex(o, warnAt, criticalAt) {
    const rl = o?.rate_limit;
    if (!rl || typeof rl !== "object")
        return null;
    const windows = [];
    for (const w of [rl.primary_window, rl.secondary_window]) {
        const p = percentOf(w?.used_percent);
        if (!w || !isFinite(p))
            continue;
        const at = Number(w.reset_at) > 0 ? Number(w.reset_at) * 1000 : 0;
        windows.push(windowOf(windowName(w.limit_window_seconds), p, at,
                              rl.limit_reached === true && p >= 100 ? "critical" : "", warnAt, criticalAt));
    }
    if (windows.length === 0)
        return null;
    return { windows: windows, plan: planName(o.plan_type), reached: rl.limit_reached === true };
}

// "free" -> "Free", "max" -> "Max".
function planName(s) {
    const t = label(s, "");
    return t === "" ? "" : t.charAt(0).toUpperCase() + t.substring(1);
}

// Claude's plan from its sign-in file (subscriptionType "max",
// rateLimitTier "…_max_20x"), if it says.
function claudePlan(type, tier) {
    const name = planName(type);
    const times = typeof tier === "string" ? /(\d+)x$/.exec(tier) : null;
    return name !== "" && times ? name + " " + times[1] + "×" : name;
}

// A token or id is only ever used if it's one plain word (no line breaks,
// spaces or colons that could add a header of their own).
function plainToken(s) {
    return typeof s === "string" && /^[A-Za-z0-9._~+\/=-]{16,8192}$/.test(s);
}
function plainId(s) {
    return typeof s === "string" && /^[A-Za-z0-9._-]{1,128}$/.test(s);
}

// A JWT's expiry (ms), from its middle part; 0 when it has none.
function jwtExpiry(token) {
    const parts = String(token).split(".");
    if (parts.length !== 3)
        return 0;
    try {
        const exp = Number(JSON.parse(base64url(parts[1])).exp);
        return isFinite(exp) && exp > 0 ? exp * 1000 : 0;
    } catch (e) {
        return 0;
    }
}

function base64url(s) {
    const abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    const t = s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    let bits = 0, n = 0, bytes = [];
    for (const ch of t) {
        const v = abc.indexOf(ch);
        if (v < 0)
            throw new Error("not base64");
        bits = (bits << 6) | v;
        n += 6;
        if (n >= 8) {
            n -= 8;
            bytes.push((bits >> n) & 0xff);
        }
    }
    // UTF-8 bytes to text.
    let out = "";
    for (let i = 0; i < bytes.length; i++) {
        const b = bytes[i];
        if (b < 0x80) {
            out += String.fromCharCode(b);
        } else if (b >= 0xc0 && b < 0xe0) {
            out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[++i] & 0x3f));
        } else if (b >= 0xe0 && b < 0xf0) {
            out += String.fromCharCode(((b & 0x0f) << 12) | ((bytes[++i] & 0x3f) << 6) | (bytes[++i] & 0x3f));
        } else {
            i += 3;
            out += "?";
        }
    }
    return out;
}

// "2 h 14 m", "14 m", "under a minute".
function untilText(ms) {
    const m = Math.max(0, Math.round(ms / 60000));
    if (m < 1)
        return "under a minute";
    const h = Math.floor(m / 60);
    return h > 0 ? h + " h" + (m % 60 > 0 ? " " + (m % 60) + " m" : "") : m + " m";
}

const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// When a window starts over: "resets in 2 h 14 m" within a day, "resets
// Wed 13:59" within a week, "resets 23 Nov" after that.
function resetText(at, now, use24h) {
    if (!(at > 0))
        return "";
    const left = at - now;
    if (left <= 0)
        return "resets now";
    if (left < 86400000)
        return "resets in " + untilText(left);
    const d = new Date(at);
    if (left < 7 * 86400000) {
        const h = d.getHours(), mi = String(d.getMinutes()).padStart(2, "0");
        const time = use24h ? String(h).padStart(2, "0") + ":" + mi : ((h + 11) % 12 + 1) + ":" + mi + (h < 12 ? " AM" : " PM");
        return "resets " + days[d.getDay()] + " " + time;
    }
    return "resets " + d.getDate() + " " + months[d.getMonth()];
}

// "just now", "3 min ago", "2 h ago".
function agoText(at, now) {
    const m = Math.floor((now - at) / 60000);
    if (m < 1)
        return "just now";
    if (m < 60)
        return m + " min ago";
    return Math.floor(m / 60) + " h ago";
}
