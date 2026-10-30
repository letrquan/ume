// Screen time's counting as plain functions: services/ScreenTime.qml keeps
// the state and calls these; the tests call them with made-up times.
//
// days: { "YYYY-MM-DD": { "<app id>": seconds } }. The dates are local (a
// day starts at your midnight, not UTC's), so a stretch over midnight is
// split between the two days.
.pragma library

function pad(n) {
    return String(n).padStart(2, "0");
}

// The local date of a time (ms since the epoch), as a key.
function dayKey(ms) {
    const d = new Date(ms);
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
}

// The first moment of the local day after `ms`.
function nextMidnight(ms) {
    const d = new Date(ms);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime();
}

// The key `back` days before `ms`'s day (0 = that day).
function dayBefore(ms, back) {
    const d = new Date(ms);
    return dayKey(new Date(d.getFullYear(), d.getMonth(), d.getDate() - back).getTime());
}

// Adds the time from `from` to `to` (ms) to `app` in `days` (changed in
// place), split at midnights. Returns the seconds added. Never more than two
// days at once: a longer stretch means a missed stop, not use.
function credit(days, app, from, to) {
    if (!app || !(to > from))
        return 0;
    const end = Math.min(to, from + 2 * 86400000);
    let added = 0;
    let t = from;
    while (t < end) {
        const stop = Math.min(end, nextMidnight(t));
        const key = dayKey(t);
        const day = days[key] ?? (days[key] = {});
        const s = (stop - t) / 1000;
        day[app] = (day[app] ?? 0) + s;
        added += s;
        t = stop;
    }
    return added;
}

// Adds every app of `more` into `days` (changed in place): what was counted
// before the file was read, on top of what the file had.
function merge(days, more) {
    for (const key of Object.keys(more)) {
        const day = days[key] ?? (days[key] = {});
        for (const app of Object.keys(more[key]))
            day[app] = Math.min(86400, (day[app] ?? 0) + more[key][app]);
    }
    return days;
}

// Keeps the last `keep` days up to `now`'s (changed in place). Returns how
// many days went.
function trim(days, keep, now) {
    const oldest = dayBefore(now, Math.max(1, keep) - 1);
    let gone = 0;
    for (const key of Object.keys(days)) {
        if (key < oldest) {
            delete days[key];
            gone++;
        }
    }
    return gone;
}

function validApp(app) {
    return typeof app === "string" && app.length > 0 && app.length <= 200 && !/[\u0000-\u001f\u007f]/.test(app);
}

// The saved file back into days; anything odd in it is left out. null when
// it isn't JSON at all.
function parse(text) {
    let data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return null;
    }
    const out = {};
    const days = data?.days;
    if (!days || typeof days !== "object" || Array.isArray(days))
        return out;
    for (const key of Object.keys(days)) {
        const apps = days[key];
        if (!/^\d{4}-\d{2}-\d{2}$/.test(key) || !apps || typeof apps !== "object" || Array.isArray(apps))
            continue;
        const day = {};
        for (const app of Object.keys(apps)) {
            const s = Number(apps[app]);
            if (validApp(app) && isFinite(s) && s > 0)
                day[app] = Math.min(s, 86400);
        }
        out[key] = day;
    }
    return out;
}

// What goes into the file (tenths of a second are plenty).
function serialize(days) {
    const out = {};
    for (const key of Object.keys(days).sort()) {
        const day = {};
        for (const app of Object.keys(days[key])) {
            const s = Math.round(days[key][app] * 10) / 10;
            if (s > 0)
                day[app] = s;
        }
        out[key] = day;
    }
    return JSON.stringify({ version: 1, days: out }, null, 1) + "\n";
}

// One day's apps, most used first: [{ appId, seconds }]. `extra` (an app
// counting right now) is added on top.
function appsOf(day, extraApp, extraSeconds) {
    const all = Object.assign({}, day ?? {});
    if (extraApp && extraSeconds > 0)
        all[extraApp] = (all[extraApp] ?? 0) + extraSeconds;
    return Object.keys(all).map(a => ({ appId: a, seconds: all[a] }))
                 .filter(a => a.seconds >= 1)
                 .sort((a, b) => b.seconds - a.seconds);
}

function total(list) {
    return list.reduce((s, a) => s + a.seconds, 0);
}

// "3 h 12 m", "12 m", "40 s" (`short`: "3h 12m" for the bar).
function durationText(seconds, short) {
    const s = Math.max(0, Math.round(seconds));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sp = short ? "" : " ";
    if (h > 0)
        return h + sp + "h" + (m > 0 ? " " + m + sp + "m" : "");
    if (m > 0)
        return m + sp + "m";
    return s + sp + "s";
}

const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// A day key's weekday, "Mon".
function weekdayOf(key) {
    const [y, m, d] = key.split("-").map(Number);
    return weekdays[new Date(y, m - 1, d).getDay()];
}
