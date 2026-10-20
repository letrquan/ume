.pragma library

// Calendar files (iCalendar / .ics, e.g. Google Calendar's "secret address
// in iCal format") → events, and their repeats spread over a span of days.
//
//   parse(text)                → { zones, events } (plain data, kept in the cache)
//   expand(cal, from, to, idx) → [{ title, location, allDay, start, end, cal }]
//                                start/end in ms; all-day ones from local midnight
//
// Times: UTC ("…Z"), floating (your local time), or in a zone (TZID=…). The
// QML engine has no Intl, so a zone's offset comes from the file's own
// VTIMEZONE (Google always includes them), else from the small table below
// (fixed zones, and US / EU / AU / NZ summer time rules), else the time is
// taken as local.
//
// Repeats (RRULE): DAILY / WEEKLY (BYDAY) / MONTHLY (BYMONTHDAY, BYDAY like
// 2MO or -1FR) / YEARLY, with INTERVAL, COUNT and UNTIL; EXDATE skips one;
// a changed or cancelled single repeat (RECURRENCE-ID) replaces it.

// ---- Reading the file ------------------------------------------------------------------

// Long lines are folded: a line starting with a space or tab continues the last.
function unfold(text) {
    return text.replace(/\r\n?/g, "\n").replace(/\n[ \t]/g, "");
}

function unescapeText(v) {
    return v.replace(/\\([\\;,nN])/g, (m, c) => (c === "n" || c === "N") ? "\n" : c);
}

// "NAME;P1=a;P2="b:c":value" → { name, params, value }
function parseLine(line) {
    let quoted = false;
    let i = 0;
    for (; i < line.length; i++) {
        const c = line[i];
        if (c === '"')
            quoted = !quoted;
        else if (c === ":" && !quoted)
            break;
    }
    if (i >= line.length)
        return null;
    const parts = line.substring(0, i).split(";");
    const params = {};
    for (let k = 1; k < parts.length; k++) {
        const eq = parts[k].indexOf("=");
        if (eq > 0)
            params[parts[k].substring(0, eq).toUpperCase()] = parts[k].substring(eq + 1).replace(/^"|"$/g, "");
    }
    return { name: parts[0].toUpperCase(), params: params, value: line.substring(i + 1) };
}

// A DATE or DATE-TIME value → { allDay, f: {y, mo, d, h, mi, s}, utc, tzid }
function dateValue(value, params) {
    const m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/.exec(value.trim());
    if (!m)
        return null;
    const allDay = m[4] === undefined || (params && params.VALUE === "DATE");
    return {
        allDay: allDay,
        f: { y: +m[1], mo: +m[2], d: +m[3], h: allDay ? 0 : +m[4], mi: allDay ? 0 : +m[5], s: allDay ? 0 : +(m[6] || 0) },
        utc: m[7] === "Z",
        tzid: (params && params.TZID) || ""
    };
}

// "P1DT2H30M", "PT45M", "P2W" → ms (all-day events: whole days count).
function durationMs(v) {
    const m = /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(v.trim());
    if (!m)
        return null;
    const ms = ((+(m[2] || 0)) * 7 * 86400 + (+(m[3] || 0)) * 86400 + (+(m[4] || 0)) * 3600 + (+(m[5] || 0)) * 60 + (+(m[6] || 0))) * 1000;
    return m[1] === "-" ? -ms : ms;
}

const WEEKDAYS = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };

// "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20261231T000000Z"
function parseRule(v) {
    const r = { freq: "", interval: 1, count: 0, until: null, byday: [], bymonthday: [], bymonth: [] };
    for (const part of v.split(";")) {
        const eq = part.indexOf("=");
        if (eq < 0)
            continue;
        const key = part.substring(0, eq).toUpperCase(), val = part.substring(eq + 1);
        if (key === "FREQ")
            r.freq = val.toUpperCase();
        else if (key === "INTERVAL")
            r.interval = Math.max(1, parseInt(val) || 1);
        else if (key === "COUNT")
            r.count = parseInt(val) || 0;
        else if (key === "UNTIL")
            r.until = dateValue(val, null);
        else if (key === "BYDAY")
            r.byday = val.split(",").map(x => {
                const mm = /^([+-]?\d+)?([A-Z]{2})$/.exec(x.trim().toUpperCase());
                return mm ? { n: mm[1] ? parseInt(mm[1]) : 0, wd: WEEKDAYS[mm[2]] } : null;
            }).filter(x => x && x.wd !== undefined);
        else if (key === "BYMONTHDAY")
            r.bymonthday = val.split(",").map(x => parseInt(x)).filter(x => !isNaN(x) && x !== 0);
        else if (key === "BYMONTH")
            r.bymonth = val.split(",").map(x => parseInt(x)).filter(x => x >= 1 && x <= 12);
    }
    return r.freq !== "" ? r : null;
}

function offsetMinutes(v) {
    const m = /^([+-])(\d{2})(\d{2})/.exec(v.trim());
    return m ? (m[1] === "-" ? -1 : 1) * (+m[2] * 60 + +m[3]) : 0;
}

function parse(text) {
    const zones = {};
    const events = [];
    const stack = [];       // open components: { type, props: [] }
    let zone = null;        // the VTIMEZONE being read: { id, rules }
    let found = false;      // it was a calendar at all

    for (const raw of unfold(text).split("\n")) {
        if (raw === "")
            continue;
        const p = parseLine(raw);
        if (!p)
            continue;
        if (p.name === "BEGIN") {
            const type = p.value.trim().toUpperCase();
            if (type === "VCALENDAR")
                found = true;
            stack.push({ type: type, props: [] });
            if (type === "VTIMEZONE")
                zone = { id: "", rules: [] };
            continue;
        }
        if (p.name === "END") {
            const c = stack.pop();
            if (!c)
                continue;
            if (c.type === "VEVENT")
                readEvent(c.props, events);
            else if ((c.type === "STANDARD" || c.type === "DAYLIGHT") && zone)
                zone.rules.push(readZoneRule(c.props));
            else if (c.type === "VTIMEZONE" && zone) {
                if (zone.id !== "")
                    zones[zone.id] = zone.rules.filter(r => r !== null);
                zone = null;
            }
            continue;
        }
        const top = stack[stack.length - 1];
        if (!top)
            continue;
        if (top.type === "VTIMEZONE" && p.name === "TZID" && zone)
            zone.id = p.value.trim();
        top.props.push(p);
    }
    return found ? { zones: zones, events: events } : null;
}

function readZoneRule(props) {
    const r = { offsetFrom: 0, offsetTo: 0, start: null, rule: null };
    for (const p of props) {
        if (p.name === "TZOFFSETFROM")
            r.offsetFrom = offsetMinutes(p.value);
        else if (p.name === "TZOFFSETTO")
            r.offsetTo = offsetMinutes(p.value);
        else if (p.name === "DTSTART")
            r.start = dateValue(p.value, null);
        else if (p.name === "RRULE")
            r.rule = parseRule(p.value);
    }
    return r.start ? r : null;
}

function readEvent(props, events) {
    const e = { uid: "", title: "", location: "", start: null, end: null, duration: null, rule: null,
                exdates: [], recurrenceId: null, cancelled: false };
    for (const p of props) {
        switch (p.name) {
        case "UID": e.uid = p.value.trim(); break;
        case "SUMMARY": e.title = unescapeText(p.value).trim(); break;
        case "LOCATION": e.location = unescapeText(p.value).trim(); break;
        case "DTSTART": e.start = dateValue(p.value, p.params); break;
        case "DTEND": e.end = dateValue(p.value, p.params); break;
        case "DURATION": e.duration = durationMs(p.value); break;
        case "RRULE": e.rule = parseRule(p.value); break;
        case "EXDATE":
            for (const v of p.value.split(",")) {
                const d = dateValue(v, p.params);
                if (d)
                    e.exdates.push(d);
            }
            break;
        case "RECURRENCE-ID": e.recurrenceId = dateValue(p.value, p.params); break;
        case "STATUS": e.cancelled = p.value.trim().toUpperCase() === "CANCELLED"; break;
        }
    }
    if (e.start)
        events.push(e);
}

// ---- Time zones ----------------------------------------------------------------------------

// Zones without summer time (minutes east of UTC).
const FIXED = {
    "Asia/Ho_Chi_Minh": 420, "Asia/Saigon": 420, "Asia/Bangkok": 420, "Asia/Jakarta": 420,
    "Asia/Phnom_Penh": 420, "Asia/Vientiane": 420, "Asia/Singapore": 480, "Asia/Kuala_Lumpur": 480,
    "Asia/Shanghai": 480, "Asia/Hong_Kong": 480, "Asia/Taipei": 480, "Asia/Manila": 480,
    "Australia/Perth": 480, "Asia/Tokyo": 540, "Asia/Seoul": 540, "Australia/Brisbane": 600,
    "Asia/Kolkata": 330, "Asia/Calcutta": 330, "Asia/Dubai": 240, "Europe/Moscow": 180,
    "Europe/Istanbul": 180, "America/Phoenix": -420, "America/Sao_Paulo": -180,
    "UTC": 0, "Etc/UTC": 0, "GMT": 0, "Etc/GMT": 0
};
// Zones with summer time: [standard, summer, which rule].
const SUMMER = {
    "America/New_York": [-300, -240, "us"], "America/Toronto": [-300, -240, "us"], "America/Detroit": [-300, -240, "us"],
    "America/Chicago": [-360, -300, "us"], "America/Denver": [-420, -360, "us"],
    "America/Los_Angeles": [-480, -420, "us"], "America/Vancouver": [-480, -420, "us"], "America/Anchorage": [-540, -480, "us"],
    "Europe/London": [0, 60, "eu"], "Europe/Dublin": [0, 60, "eu"], "Europe/Lisbon": [0, 60, "eu"],
    "Europe/Paris": [60, 120, "eu"], "Europe/Berlin": [60, 120, "eu"], "Europe/Madrid": [60, 120, "eu"],
    "Europe/Rome": [60, 120, "eu"], "Europe/Amsterdam": [60, 120, "eu"], "Europe/Brussels": [60, 120, "eu"],
    "Europe/Vienna": [60, 120, "eu"], "Europe/Zurich": [60, 120, "eu"], "Europe/Stockholm": [60, 120, "eu"],
    "Europe/Oslo": [60, 120, "eu"], "Europe/Copenhagen": [60, 120, "eu"], "Europe/Warsaw": [60, 120, "eu"],
    "Europe/Prague": [60, 120, "eu"], "Europe/Budapest": [60, 120, "eu"],
    "Europe/Helsinki": [120, 180, "eu"], "Europe/Athens": [120, 180, "eu"], "Europe/Kiev": [120, 180, "eu"],
    "Europe/Kyiv": [120, 180, "eu"], "Europe/Bucharest": [120, 180, "eu"],
    "Australia/Sydney": [600, 660, "au"], "Australia/Melbourne": [600, 660, "au"], "Australia/Hobart": [600, 660, "au"],
    "Australia/Canberra": [600, 660, "au"], "Australia/Adelaide": [570, 630, "au"],
    "Pacific/Auckland": [720, 780, "nz"]
};

function ymd(f) {
    return Date.UTC(f.y, f.mo - 1, f.d, f.h, f.mi, f.s);
}
function fieldsOf(ms) {
    const d = new Date(ms);
    return { y: d.getUTCFullYear(), mo: d.getUTCMonth() + 1, d: d.getUTCDate(), h: d.getUTCHours(), mi: d.getUTCMinutes(), s: d.getUTCSeconds() };
}
function addDays(f, n) {
    return fieldsOf(Date.UTC(f.y, f.mo - 1, f.d + n, f.h, f.mi, f.s));
}
function weekday(f) {
    return new Date(Date.UTC(f.y, f.mo - 1, f.d)).getUTCDay();
}
function daysInMonth(y, mo) {
    return new Date(Date.UTC(y, mo, 0)).getUTCDate();
}
// The n-th (or n-th from the end, n < 0) weekday wd of a month; 0 if none.
function nthWeekday(y, mo, n, wd) {
    if (n > 0) {
        const first = new Date(Date.UTC(y, mo - 1, 1)).getUTCDay();
        const d = 1 + (wd - first + 7) % 7 + (n - 1) * 7;
        return d <= daysInMonth(y, mo) ? d : 0;
    }
    const last = daysInMonth(y, mo);
    const lastWd = new Date(Date.UTC(y, mo - 1, last)).getUTCDay();
    const d = last - (lastWd - wd + 7) % 7 + (n + 1) * 7;
    return d >= 1 ? d : 0;
}

// Is summer time on at this wall-clock time, by a built-in rule?
function summerOn(rule, f, standard) {
    const t = ymd(f);
    const at = (mo, n, wd, h) => Date.UTC(f.y, mo - 1, nthWeekday(f.y, mo, n, wd), h);
    if (rule === "us")
        return t >= at(3, 2, 0, 2) && t < at(11, 1, 0, 2);
    if (rule === "eu") {
        // 01:00 UTC on the last Sundays of March and October.
        const utc = t - standard * 60000;
        return utc >= at(3, -1, 0, 1) && utc < at(10, -1, 0, 1);
    }
    if (rule === "au")
        return t >= at(10, 1, 0, 2) || t < at(4, 1, 0, 3);
    if (rule === "nz")
        return t >= at(9, -1, 0, 2) || t < at(4, 1, 0, 3);
    return false;
}

// When a VTIMEZONE rule starts in year y, as wall-clock ms (null: not that year).
function transition(r, y) {
    if (y < r.start.f.y)
        return null;
    if (!r.rule)
        return y === r.start.f.y ? ymd(r.start.f) : null;
    if (r.rule.until && y > r.rule.until.f.y)
        return null;
    const mo = r.rule.bymonth[0] || r.start.f.mo;
    const by = r.rule.byday[0];
    const d = by ? nthWeekday(y, mo, by.n || 1, by.wd) : r.start.f.d;
    return d ? Date.UTC(y, mo - 1, d, r.start.f.h, r.start.f.mi, r.start.f.s) : null;
}

// Minutes east of UTC for wall-clock time f in zone tzid; null = unknown.
function zoneOffset(zones, tzid, f) {
    const rules = zones[tzid];
    if (rules && rules.length > 0) {
        const t = ymd(f);
        let best = null, bestT = -Infinity, earliest = rules[0];
        for (const r of rules) {
            if (ymd(r.start.f) < ymd(earliest.start.f))
                earliest = r;
            for (const y of [f.y - 1, f.y]) {
                const tt = transition(r, y);
                if (tt !== null && tt <= t && tt > bestT) {
                    bestT = tt;
                    best = r;
                }
            }
        }
        return (best || earliest).offsetTo;
    }
    if (FIXED[tzid] !== undefined)
        return FIXED[tzid];
    const s = SUMMER[tzid];
    if (s)
        return summerOn(s[2], f, s[0]) ? s[1] : s[0];
    // "Etc/GMT-7" means UTC+7 (the sign is backwards).
    let m = /^Etc\/GMT([+-])(\d{1,2})$/.exec(tzid);
    if (m)
        return (m[1] === "-" ? 1 : -1) * (+m[2]) * 60;
    // Outlook-style names: "(UTC+07:00) Bangkok, Hanoi, Jakarta".
    m = /UTC([+-])(\d{2}):?(\d{2})/.exec(tzid);
    if (m)
        return (m[1] === "-" ? -1 : 1) * (+m[2] * 60 + +m[3]);
    return null;
}

// A timed value → ms. Unknown zones and floating times are local time.
function epoch(v, zones) {
    if (v.utc)
        return ymd(v.f);
    if (v.tzid !== "") {
        const off = zoneOffset(zones, v.tzid, v.f);
        if (off !== null)
            return ymd(v.f) - off * 60000;
    }
    return new Date(v.f.y, v.f.mo - 1, v.f.d, v.f.h, v.f.mi, v.f.s).getTime();
}
// The same wall-clock fields in the frame of `like` (its zone, UTC or local).
function epochLike(f, like, zones) {
    return epoch({ allDay: false, f: f, utc: like.utc, tzid: like.tzid }, zones);
}
function localMidnight(f) {
    return new Date(f.y, f.mo - 1, f.d).getTime();
}
// Zones nobody could place (shown once in the log, without the event).
function unknownZones(cal) {
    const out = {};
    for (const e of cal.events)
        for (const v of [e.start, e.end])
            if (v && !v.allDay && !v.utc && v.tzid !== "" && zoneOffset(cal.zones, v.tzid, v.f) === null)
                out[v.tzid] = true;
    return Object.keys(out);
}

// ---- Repeats -------------------------------------------------------------------------------

// Wall-clock starts of a repeating event, in order (its own frame), until
// the rule ends, `toMs` is passed, or `limit` were made.
function starts(e, zones, toMs, limit) {
    const r = e.rule, s = e.start.f, out = [];
    const untilMs = r.until ? (r.until.allDay ? localMidnight(r.until.f) + 86400000 - 1 : epoch(r.until, zones)) : Infinity;
    const timeOf = f => e.start.allDay ? localMidnight(f) : epochLike(f, e.start, zones);
    const keep = f => {
        const t = timeOf(f);
        if (t < timeOf(s))
            return true;            // before the first one (BYDAY earlier in its week)
        if (t > untilMs || t > toMs || (r.count && out.length >= r.count))
            return false;
        out.push(f);
        return out.length < limit;
    };
    const withTime = (y, mo, d) => ({ y: y, mo: mo, d: d, h: s.h, mi: s.mi, s: s.s });

    if (r.freq === "DAILY") {
        for (let i = 0; i < limit * r.interval; i += r.interval)
            if (!keep(addDays(s, i)))
                break;
    } else if (r.freq === "WEEKLY") {
        const days = r.byday.length ? r.byday.map(b => b.wd) : [weekday(s)];
        // Weeks start on Monday (WKST=MO).
        const monday = addDays(s, -((weekday(s) + 6) % 7));
        const order = days.map(wd => (wd + 6) % 7).sort((a, b) => a - b);
        let going = true;
        for (let w = 0; going && w < limit * r.interval; w += r.interval)
            for (const k of order)
                if (!(going = keep(addDays(monday, w * 7 + k))))
                    break;
    } else if (r.freq === "MONTHLY") {
        let going = true;
        for (let i = 0; going && i < limit * r.interval; i += r.interval) {
            const y = s.y + Math.floor((s.mo - 1 + i) / 12), mo = (s.mo - 1 + i) % 12 + 1;
            const dim = daysInMonth(y, mo);
            let ds = [];
            if (r.bymonthday.length)
                ds = r.bymonthday.map(d => d > 0 ? d : dim + 1 + d);
            else if (r.byday.length) {
                for (const b of r.byday) {
                    if (b.n !== 0)
                        ds.push(nthWeekday(y, mo, b.n, b.wd));
                    else
                        for (let d = nthWeekday(y, mo, 1, b.wd); d && d <= dim; d += 7)
                            ds.push(d);
                }
            } else
                ds = [s.d];
            ds = ds.filter(d => d >= 1 && d <= dim).sort((a, b) => a - b);
            for (const d of ds)
                if (!(going = keep(withTime(y, mo, d))))
                    break;
        }
    } else if (r.freq === "YEARLY") {
        const months = r.bymonth.length ? r.bymonth : [s.mo];
        let going = true;
        for (let i = 0; going && i < limit * r.interval; i += r.interval) {
            const y = s.y + i;
            for (const mo of months) {
                const b = r.byday[0];
                const d = b && b.n !== 0 ? nthWeekday(y, mo, b.n, b.wd) : s.d;
                if (d < 1 || d > daysInMonth(y, mo))
                    continue;           // e.g. 29 February
                if (!(going = keep(withTime(y, mo, d))))
                    break;
            }
        }
    }
    return out;
}

// Every occurrence of a calendar's events that overlaps [fromMs, toMs).
function expand(cal, fromMs, toMs, index) {
    const zones = cal.zones || {};
    const out = [];
    // Changed or cancelled single repeats, by UID.
    const changed = {};
    for (const e of cal.events)
        if (e.recurrenceId) {
            (changed[e.uid] = changed[e.uid] || []).push(e.recurrenceId.allDay ? localMidnight(e.recurrenceId.f) : epoch(e.recurrenceId, zones));
        }

    const add = (e, startMs, endMs) => {
        if (endMs > fromMs && startMs < toMs)
            out.push({ title: e.title || "(No title)", location: e.location, allDay: e.start.allDay,
                       start: startMs, end: endMs, cal: index });
    };
    const lengthOf = e => {
        if (e.end) {
            if (e.start.allDay)
                return Math.max(1, Math.round((Date.UTC(e.end.f.y, e.end.f.mo - 1, e.end.f.d) - Date.UTC(e.start.f.y, e.start.f.mo - 1, e.start.f.d)) / 86400000)) * 86400000;
            return Math.max(0, epoch(e.end, zones) - epoch(e.start, zones));
        }
        if (e.duration !== null)
            return Math.max(0, e.duration);
        return e.start.allDay ? 86400000 : 0;
    };

    for (const e of cal.events) {
        if (e.cancelled)
            continue;
        const len = lengthOf(e);
        // All-day: from local midnight; several days = len in whole days.
        const span = (f, t) => e.start.allDay ? localMidnight(addDays(f, Math.round(len / 86400000))) : t + len;
        if (e.recurrenceId || !e.rule) {
            const t = e.start.allDay ? localMidnight(e.start.f) : epoch(e.start, zones);
            add(e, t, span(e.start.f, t));
            continue;
        }
        const skip = e.exdates.map(x => x.allDay ? localMidnight(x.f) : epoch(x, zones)).concat(changed[e.uid] || []);
        for (const f of starts(e, zones, toMs, 3000)) {
            const t = e.start.allDay ? localMidnight(f) : epochLike(f, e.start, zones);
            if (skip.some(x => Math.abs(x - t) < 60000 || (e.start.allDay && x >= t && x < t + 86400000)))
                continue;
            add(e, t, span(f, t));
        }
    }
    return out;
}
