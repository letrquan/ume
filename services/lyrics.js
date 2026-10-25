.pragma library

// Song lyrics from lrclib.net (services/Lyrics.qml): reading the LRC text
// it sends, cleaning song names up before a search, and picking the best
// of the search results. No QML in here, so node can test it (strip the
// first line).
//
// LRC: "[01:12.34]a line", several stamps on one line ("[00:10.00][01:10.00]
// chorus"), [offset:+250] (ms; plus = the lines come that much earlier),
// tags like [ar:…] [ti:…] [length:…] (skipped), word stamps <01:12.50>
// inside a line (dropped), blank stamped lines = a pause in the singing.

// "01:12.34" / "1:12" / "01:12:34" (centiseconds after a colon) → seconds.
function stamp(s) {
    const m = /^(\d+):(\d{1,2})(?:[.:](\d{1,3}))?$/.exec(s.trim());
    if (!m)
        return -1;
    const frac = m[3] ? Number(m[3]) / Math.pow(10, m[3].length) : 0;
    return Number(m[1]) * 60 + Number(m[2]) + frac;
}

// → { synced: [{ t, text }] sorted by t (text "" = a pause),
//     plain: [lines] (the text without stamps, blank lines kept once) }
function parse(text) {
    const synced = [];
    const plain = [];
    let offset = 0;
    const rows = String(text ?? "").replace(/\r\n?/g, "\n").split("\n");
    for (const raw of rows) {
        let line = raw.trim();
        const times = [];
        let tags = 0;
        let m;
        // Leading [..] groups: stamps or tags.
        while ((m = /^\[([^\]]*)\]/.exec(line)) !== null) {
            const t = stamp(m[1]);
            if (t >= 0) {
                times.push(t);
            } else {
                tags++;
                const off = /^offset:\s*([+-]?\d+)/i.exec(m[1]);
                if (off)
                    offset = Number(off[1]) / 1000;
            }
            line = line.slice(m[0].length).replace(/^\s+/, "");
        }
        // Word stamps, and the spaces they leave.
        line = line.replace(/<\d+:\d{1,2}(?:[.:]\d{1,3})?>/g, "").replace(/\s{2,}/g, " ").trim();
        if (times.length === 0 && tags > 0 && line === "")
            continue;   // a tag line ([ar:…], [length:…])
        for (const t of times)
            synced.push({ t: t, text: line });
        // Plain text: blank lines only between verses, once.
        if (line !== "" || (plain.length > 0 && plain[plain.length - 1] !== ""))
            plain.push(line);
    }
    while (plain.length > 0 && plain[plain.length - 1] === "")
        plain.pop();
    if (offset !== 0)
        for (const l of synced)
            l.t = Math.max(0, l.t - offset);
    synced.sort((a, b) => a.t - b.t);
    // A pause right after a pause says nothing new.
    const out = [];
    for (const l of synced)
        if (!(l.text === "" && out.length > 0 && out[out.length - 1].text === ""))
            out.push(l);
    // Nothing but pauses: not really synced lyrics.
    return { synced: out.some(l => l.text !== "") ? out : [], plain: plain };
}

// Plain lyrics (no stamps): lines, one blank line between verses at most.
function plainLines(text) {
    return parse(text).plain;
}

// The line showing at `t` seconds: the last one that started; -1 before
// the first.
function indexAt(lines, t) {
    let lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
        const mid = (lo + hi) >> 1;
        if (lines[mid].t <= t) {
            found = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    return found;
}

// Words that say which recording or edit it is, not what the song is
// called: " - Remastered 2011", "(feat. X)", "[Live]", " - Radio Edit"…
const extra = "feat\\.?|ft\\.?|featuring|with |remaster(?:ed)?|\\d{4} remaster|live|radio edit|edit|version|mono|stereo|deluxe|bonus|explicit|clean|acoustic|demo|single|mix|remix|from |original|instrumental|sped up|slowed";
const bracketRe = new RegExp("\\s*[\\(\\[]\\s*(?:[^\\)\\]]*?\\b)?(?:" + extra + ")(?![a-z])[^\\)\\]]*[\\)\\]]", "gi");
const dashRe = new RegExp("\\s+[-\u2013\u2014]\\s+(?:[^-\u2013\u2014]*?\\b)?(?:" + extra + ")(?![a-z]).*$", "i");

function cleanTitle(s) {
    let t = String(s ?? "");
    t = t.replace(bracketRe, "");
    t = t.replace(dashRe, "");
    return t.replace(/\s{2,}/g, " ").trim() || String(s ?? "").trim();
}

// The first artist of "A, B", "A & B", "A feat. B", "A x B".
function firstArtist(s) {
    const a = String(s ?? "").split(/\s*(?:,|;|&|\bfeat\.?|\bft\.?|\bfeaturing\b|\s\/\s|\sx\s|\svs\.?\s)\s*/i)[0];
    return (a ?? "").trim() || String(s ?? "").trim();
}

// For comparing names: lower case, no accents, letters and digits only
// (Latin, Greek, Cyrillic, CJK, kana, Hangul; QML's engine has no \p{L}).
function loose(s) {
    return String(s ?? "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .replace(/\u0111/g, "d")
        .replace(/[^a-z0-9\u00df-\u024f\u0370-\u03ff\u0400-\u04ff\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]+/g, " ").trim();
}

// The best of lrclib's /api/search results for what's playing, or null.
// Its length must be within 2 s (when we know ours); synced lyrics beat
// plain ones, a title that matches beats one that doesn't.
//   want: { title, artist, duration }
function choose(results, want) {
    if (!Array.isArray(results))
        return null;
    const d = Number(want?.duration ?? 0);
    const title = loose(cleanTitle(want?.title));
    const artist = loose(firstArtist(want?.artist));
    let best = null, bestScore = -1;
    for (const r of results) {
        if (!r || typeof r !== "object")
            continue;
        const rd = Number(r.duration ?? 0);
        if (d > 0 && rd > 0 && Math.abs(rd - d) > 2)
            continue;
        const hasSynced = typeof r.syncedLyrics === "string" && r.syncedLyrics.trim() !== "";
        const hasPlain = typeof r.plainLyrics === "string" && r.plainLyrics.trim() !== "";
        if (!hasSynced && !hasPlain && !r.instrumental)
            continue;
        let score = 0;
        if (hasSynced)
            score += 100;
        else if (hasPlain)
            score += 40;
        const rt = loose(cleanTitle(r.trackName ?? r.name ?? ""));
        if (title !== "" && rt === title)
            score += 30;
        else if (title !== "" && (rt.includes(title) || title.includes(rt)))
            score += 10;
        const ra = loose(r.artistName ?? "");
        if (artist !== "" && (ra === artist || ra.includes(artist)))
            score += 20;
        if (d > 0 && rd > 0)
            score += 5 - Math.abs(rd - d) * 2;
        if (score > bestScore) {
            best = r;
            bestScore = score;
        }
    }
    return best;
}

// A file name for the cache: readable bits plus a hash of all of it.
function cacheKey(artist, title, album, duration) {
    const all = [artist, title, album, Math.round(Number(duration) || 0)].join("\u0001");
    let h = 5381;
    for (let i = 0; i < all.length; i++)
        h = ((h * 33) ^ all.charCodeAt(i)) >>> 0;
    const slug = loose(firstArtist(artist) + " " + cleanTitle(title)).replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "").slice(0, 48);
    return (slug || "song") + "-" + h.toString(16).padStart(8, "0");
}

// The fixture file name for a song (tests: MINE_LYRICS_FIXTURE).
function fixtureName(title) {
    return loose(cleanTitle(title)).replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "song";
}
