pragma Singleton
import QtQuick
import Quickshell

// Finds settings by what they say: each row of Sections.qml by its label,
// description, its group's and section's titles, its knob's name
// ("dockBehavior" = "dock behavior"), its choices and its button. Only what
// rows already have, so a new row is found without doing anything. Never
// calls a row's functions (status, text, get, run): those reach into the
// services (the phone, the weather...).
//
// A row is known by a ref: "<section id>/<knob name>", or for a row without
// a knob "<section id>/<group title>/<key or label>". It stays the same when
// rows are added around it.
//
// Used by the Settings window's search field and by the launcher (typing
// "dock" there shows Settings › Dock › … rows too).
Singleton {
    id: root

    // How much a word found in each part of a row counts.
    readonly property var weights: ({ label: 100, group: 70, section: 60, key: 55, choices: 45, desc: 40 })

    // Every row once, in the window's order:
    // { ref, order, section, sectionTitle, icon, group, row, title, path, f: { label, group, ... } }
    readonly property var index: build(Sections.list)

    // Lower case, accents off ("é" = "e"), for comparing.
    function norm(s) {
        const t = String(s ?? "");
        return (t.normalize ? t.normalize("NFD").replace(/[̀-ͯ]/g, "") : t).toLowerCase();
    }

    // dockBehavior -> "dock behavior"
    function spaced(name) {
        return String(name ?? "").replace(/([a-z0-9])([A-Z])/g, "$1 $2");
    }

    function refOf(section, group, row) {
        if (row.name)
            return section.id + "/" + row.name;
        return section.id + "/" + (group?.title ?? "") + "/" + (row.key ?? row.label ?? "");
    }

    function build(sections) {
        const out = [];
        for (const s of sections ?? []) {
            const groups = s.groups ?? [{ title: "", rows: s.rows ?? [] }];
            for (const g of groups) {
                for (const r of g.rows ?? []) {
                    const groupTitle = g.title ?? "";
                    out.push({
                        ref: refOf(s, g, r),
                        order: out.length,
                        section: s.id,
                        sectionTitle: s.title,
                        icon: s.icon,
                        group: groupTitle,
                        row: r,
                        // What a result is called: the label, or (the bar items
                        // editors have none) the group's title.
                        title: r.label || groupTitle || s.title,
                        path: s.title + (groupTitle !== "" ? " › " + groupTitle : ""),
                        f: {
                            label: norm(r.label),
                            group: norm(groupTitle),
                            section: norm(s.title),
                            key: norm(spaced(r.name ?? r.key ?? "")),
                            choices: norm((r.choices ?? []).map(c => c.label ?? "").concat([r.button ?? ""]).join(" ")),
                            desc: norm(r.desc)
                        }
                    });
                }
            }
        }
        return out;
    }

    // How well a word fits a text: 1 the whole of it, 0.9 its start, 0.8 the
    // start of one of its words, 0.5 somewhere inside (3 letters or more), 0.
    function quality(text, word) {
        if (text === "" || word === "")
            return 0;
        if (text === word)
            return 1;
        if (text.startsWith(word))
            return 0.9;
        let at = text.indexOf(word);
        if (at < 0)
            return 0;
        while (at > 0) {
            if (!/[a-z0-9]/.test(text[at - 1]))
                return 0.8;
            at = text.indexOf(word, at + 1);
        }
        return word.length >= 3 ? 0.5 : 0;
    }

    function wordsOf(query) {
        return norm(query).split(/\s+/).filter(w => w !== "");
    }

    // A row's score for these words (0: one of them is nowhere). Each word
    // counts where it fits best; all of them in the label adds a bit.
    // `withSection` false: the section's title doesn't count (the launcher
    // has a result for the section itself).
    function scoreOf(e, words, withSection) {
        let total = 0;
        let allInLabel = true;
        for (const w of words) {
            let best = 0;
            for (const part in weights) {
                if (!withSection && part === "section")
                    continue;
                const q = quality(e.f[part], w);
                if (q > 0)
                    best = Math.max(best, weights[part] * q);
            }
            if (best === 0)
                return 0;
            if (quality(e.f.label, w) < 0.8)
                allInLabel = false;
            total += best;
        }
        return total / words.length + (allInLabel ? 20 : 0);
    }

    // The rows that match, best first: [{ e, score }]
    function find(query) {
        const words = wordsOf(query);
        if (words.length === 0)
            return [];
        const out = [];
        for (const e of index) {
            const s = scoreOf(e, words, true);
            if (s > 0)
                out.push({ e: e, score: s });
        }
        out.sort((a, b) => b.score - a.score || a.e.order - b.e.order);
        return out;
    }

    // For the Settings window: the matches in groups ("Dock › Behaviour"),
    // the group with the best match first.
    //   { groups: [{ title, section, icon, rows, refs, start }], refs (all, in
    //     order), total, counts: { <section id>: matches } }
    function grouped(query) {
        const groups = [];
        const byKey = {};
        const counts = {};
        for (const m of find(query)) {
            const key = m.e.section + "\n" + m.e.group;
            let g = byKey[key];
            if (!g) {
                g = byKey[key] = { title: m.e.path, section: m.e.section, icon: m.e.icon, rows: [], refs: [] };
                groups.push(g);
            }
            g.rows.push(m.e.row);
            g.refs.push(m.e.ref);
            counts[m.e.section] = (counts[m.e.section] ?? 0) + 1;
        }
        const refs = [];
        for (const g of groups) {
            g.start = refs.length;
            for (const r of g.refs)
                refs.push(r);
        }
        return { groups: groups, refs: refs, total: refs.length, counts: counts };
    }

    // A row by its ref (null if it's gone).
    function locate(ref) {
        return index.find(e => e.ref === ref) ?? null;
    }

    // For the launcher: up to `most` results (2 letters or more), a section
    // first when its title fits, then rows (by their own words: label,
    // group, knob, choices, description). Each has `score` for ranking.
    //   { kind: "setting", title, subtitle: "Settings › Dock › Behaviour",
    //     icon, value: { section, ref }, score }
    function launcherResults(query, most) {
        const words = wordsOf(query);
        if (words.join("").length < 2)
            return [];
        const out = [];
        const sectionsShown = {};
        for (const s of Sections.list) {
            const title = norm(s.title);
            let sum = 0;
            for (const w of words) {
                const q = quality(title, w);
                sum = q >= 0.8 ? sum + q : -1e9;
            }
            if (sum <= 0)
                continue;
            sectionsShown[s.id] = norm(s.title);
            out.push({ kind: "setting", title: s.title, subtitle: "Settings", icon: s.icon,
                       value: { section: s.id, ref: "" }, score: 100 * sum / words.length + 30 });
        }
        for (const e of index) {
            // "Wallpaper" in Wallpaper: the section's own result says it.
            if (sectionsShown[e.section] === e.f.label)
                continue;
            const s = scoreOf(e, words, false);
            // A word only in the description (or inside a word) isn't enough
            // here: the window's own search has those.
            if (s < 40)
                continue;
            out.push({ kind: "setting", title: e.title, subtitle: "Settings › " + e.path, icon: e.icon,
                       value: { section: e.section, ref: e.ref }, score: s });
        }
        // Equal scores keep the window's order (sections before their rows).
        out.forEach((r, i) => r.n = i);
        out.sort((a, b) => b.score - a.score || a.n - b.n);
        return out.slice(0, most ?? 4);
    }
}
