pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Arch news for the updates panel: the items of archlinux.org's news feed
// newer than your last full upgrade (the last "[PACMAN] starting full
// system upgrade" line of pacman.log, found from the end: `tac | grep -m1`,
// never reading the whole file). They're the ones that sometimes say "do
// this by hand before updating".
//
// The feed is read at check time and when the panel opens, at most every
// 3 hours (curl, 15 s at most), and kept in ~/.cache/mine-shell/
// arch-news.json so it's there at once after a restart. Style.updatesNews
// off: never read.
//
// Tests: MINE_UPDATES_NEWS (the feed's address, e.g. file:///…/news.xml),
// MINE_UPDATES_NEWS_CACHE (instead of arch-news.json); MINE_UPDATES_DRYRUN
// or MINE_UPDATES_FAKE: a link is only printed, not opened.
Singleton {
    id: root

    readonly property string url: Quickshell.env("MINE_UPDATES_NEWS") || "https://archlinux.org/feeds/news/"
    readonly property string cachePath: Quickshell.env("MINE_UPDATES_NEWS_CACHE")
        || (Quickshell.env("HOME") + "/.cache/mine-shell/arch-news.json")
    readonly property bool printOnly: Quickshell.env("MINE_UPDATES_DRYRUN") === "1"
        || (Quickshell.env("MINE_UPDATES_FAKE") ?? "") !== ""
    readonly property int maxAge: 3 * 3600000

    // Newest first: { title, link, date (ms) }.
    property var items: []
    property double fetchedAt: 0
    property bool fetching: false
    // When the last full upgrade started (ms), 0 = not known (yet).
    property double lastUpgrade: 0
    readonly property var fresh: !Style.updatesNews || lastUpgrade <= 0 ? []
        : items.filter(i => i.date > lastUpgrade).slice(0, 5)

    // At check time and when the panel opens: the last upgrade again (it
    // moves after each one), and the feed if it's old.
    function refresh() {
        readUpgrade();
        if (!Style.updatesNews || fetching || Date.now() - fetchedAt < maxAge)
            return;
        fetching = true;
        feed.running = true;
    }

    function readUpgrade() {
        if (!upgrade.running)
            upgrade.running = true;
    }

    Process {
        id: upgrade
        command: ["sh", "-c", 'tac -- "$1" 2>/dev/null | grep -m1 -F "[PACMAN] starting full system upgrade"',
                  "sh", Updates.logPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const at = root.alpmDate(text);
                if (at > 0)
                    root.lastUpgrade = at;
            }
        }
    }

    Process {
        id: feed
        command: ["curl", "-fsSL", "--max-time", "15", "--proto-redir", "=https", "--", root.url]
        stdout: StdioCollector {
            id: feedText
        }
        onExited: code => {
            root.fetching = false;
            if (code !== 0) {
                console.log("updates: couldn't read the Arch news (curl " + code + ")");
                return;
            }
            const got = root.parse(feedText.text);
            if (got.length === 0) {
                console.log("updates: no Arch news in what came back");
                return;
            }
            root.items = got;
            root.fetchedAt = Date.now();
            cache.setText(JSON.stringify({ fetchedAt: root.fetchedAt, items: root.items }) + "\n");
        }
    }

    function ours(link) {
        return /^https:\/\/(www\.)?archlinux\.org\//.test(String(link ?? ""));
    }
    function open(item) {
        const link = String(item?.link ?? "");
        if (!ours(link))
            return;
        if (printOnly)
            console.log("updates (dry run):", JSON.stringify(["xdg-open", link]));
        else
            Quickshell.execDetached(["xdg-open", link]);
    }

    // ---- Reading -----------------------------------------------------------------------
    // "[2026-10-22T16:12:34+0700] …" → ms
    function alpmDate(line) {
        const m = /\[(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)([+-])(\d\d):?(\d\d)\]/.exec(String(line ?? ""));
        if (!m)
            return 0;
        const offset = (m[7] === "-" ? -1 : 1) * (Number(m[8]) * 60 + Number(m[9])) * 60000;
        return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6])) - offset;
    }

    // RSS pubDate: "Tue, 14 Oct 2026 10:00:00 +0000" → ms
    readonly property var months: ({ Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5, Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11 })
    function rssDate(text) {
        const m = /(\d{1,2}) (\w{3}) (\d{4}) (\d\d):(\d\d)(?::(\d\d))? ?([+-]\d{4}|GMT|UTC|Z)?/.exec(String(text ?? ""));
        if (!m || months[m[2]] === undefined)
            return 0;
        let offset = 0;
        if (m[7] && /^[+-]/.test(m[7]))
            offset = (m[7][0] === "-" ? -1 : 1) * (Number(m[7].slice(1, 3)) * 60 + Number(m[7].slice(3, 5))) * 60000;
        return Date.UTC(Number(m[3]), months[m[2]], Number(m[1]), Number(m[4]), Number(m[5]), Number(m[6] ?? 0)) - offset;
    }

    function plain(text) {
        return String(text ?? "").replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
            .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
            .replace(/&#39;|&apos;/g, "'").replace(/&#(\d+);/g, (all, n) => String.fromCharCode(Number(n)))
            .replace(/&amp;/g, "&").replace(/\s+/g, " ").trim();
    }
    function tag(body, name) {
        const m = new RegExp("<" + name + "(?:\\s[^>]*)?>([\\s\\S]*?)</" + name + ">").exec(body);
        return m ? m[1] : "";
    }
    function parse(xml) {
        const out = [];
        const re = /<item(?:\s[^>]*)?>([\s\S]*?)<\/item>/g;
        let m;
        while ((m = re.exec(String(xml ?? ""))) !== null) {
            const title = plain(tag(m[1], "title"));
            const link = plain(tag(m[1], "link"));
            const date = rssDate(plain(tag(m[1], "pubDate")));
            // Only Arch's own pages (what comes back is text from the internet).
            if (title !== "" && date > 0 && root.ours(link))
                out.push({ title: title, link: link, date: date });
        }
        out.sort((a, b) => b.date - a.date);
        return out.slice(0, 20);
    }

    // "14 Oct"
    function day(ms) {
        const d = new Date(ms);
        return d.getDate() + " " + Object.keys(months)[d.getMonth()];
    }

    // ---- Kept between starts ---------------------------------------------------------------
    FileView {
        id: cache
        path: root.cachePath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const c = JSON.parse(text() || "{}");
                if (root.items.length === 0 && Array.isArray(c.items)) {
                    root.items = c.items;
                    root.fetchedAt = c.fetchedAt ?? 0;
                }
            } catch (e) {}
        }
    }
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", cachePath.substring(0, cachePath.lastIndexOf("/"))])
}
