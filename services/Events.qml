pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "events.js" as Ics

// Your calendar events, for the calendar card (click the clock) and the
// next one next to the clock. They come from calendar files on the web:
// Style.calendarIcsUrls, e.g. Google Calendar's "Secret address in iCal
// format" (several: spaces between). Fetched with curl when the shell
// starts (if the saved copy is older than Style.calendarRefreshMinutes) and
// then every calendarRefreshMinutes, only while there's an address. The
// events are kept in ~/.local/state/mine-shell/events.json (without the
// addresses), so the card shows them at once, and also offline.
//
// The addresses are secret (anyone with one can read that calendar): they
// go to curl on its stdin, never on its command line, and are never logged.
// The saved copy only keeps a fingerprint of each, to know it's still the
// same calendar.
//
// Repeats are spread over the months around today (Ics.expand); times in
// other zones follow the file's own zone rules (see events.js).
//
// Tests: MINE_EVENTS_FILE (.ics files, spaces between, read instead of the
// addresses), MINE_EVENTS_CACHE (where the copy goes).
Singleton {
    id: root

    readonly property var testFiles: (Quickshell.env("MINE_EVENTS_FILE") || "").split(/\s+/).filter(f => f !== "")
    readonly property var sources: testFiles.length > 0 ? testFiles.map(f => "file://" + f)
        : Style.calendarIcsUrls.split(/\s+/).filter(u => u !== "")
    readonly property bool enabled: sources.length > 0
    readonly property string cachePath: Quickshell.env("MINE_EVENTS_CACHE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/events.json")

    // One per source, in order: { fp, fetchedAt, zones, events } or null.
    property var calendars: []
    // Every occurrence around today, by local day "2026-10-15" (all-day
    // first, then by time), and all of them in order.
    property var byDay: ({})
    property var occurrences: []
    // Bumps on every change (for bindings that call the functions below).
    property int revision: 0
    property bool fetching: false
    // What went wrong last time, in words (never the address).
    property string status: ""

    // ---- For the calendar card ------------------------------------------------------------
    function dayKey(d) {
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    }
    function on(d) {
        return byDay[dayKey(d)] ?? [];
    }
    function count(d) {
        return (byDay[dayKey(d)] ?? []).length;
    }
    // The first event starting after `ms` (and not on the same day as `ms`
    // when notToday), or null.
    function nextAfter(ms, notToday) {
        const today = dayKey(new Date(ms));
        for (const o of occurrences)
            if (o.start > ms && !(notToday && dayKey(new Date(o.start)) === today))
                return o;
        return null;
    }
    // A timed event starting within the next hour (the clock shows it).
    readonly property var soon: {
        const t = clock.date.getTime();
        for (const o of occurrences)
            if (!o.allDay && o.start >= t - 60000 && o.start - t <= 3600000)
                return o;
        return null;
    }

    // One color per calendar (the order of the addresses).
    function colorOf(i) {
        const list = [Colors.primary, Colors.tertiary, Colors.secondary, Colors.error];
        return list[i % list.length];
    }
    function time(ms) {
        return Qt.formatTime(new Date(ms), Style.clock24h ? "HH:mm" : "h:mm AP");
    }

    // ---- Spreading the repeats --------------------------------------------------------------
    function rebuild() {
        const now = new Date();
        const from = new Date(now.getFullYear(), now.getMonth() - 1, 1).getTime();
        const to = new Date(now.getFullYear(), now.getMonth() + 4, 1).getTime();
        let all = [];
        calendars.forEach((cal, i) => {
            if (cal)
                all = all.concat(Ics.expand(cal, from, to, i));
        });
        all.sort((a, b) => a.start - b.start || (b.allDay - a.allDay));
        const days = {};
        for (const o of all) {
            // Every day it touches (an event ending at midnight doesn't touch the next).
            const first = new Date(o.start);
            const day = new Date(first.getFullYear(), first.getMonth(), first.getDate());
            const last = Math.max(o.start, o.end - 1);
            for (let n = 0; n < 62 && day.getTime() <= last; n++) {
                (days[dayKey(day)] = days[dayKey(day)] || []).push(o);
                day.setDate(day.getDate() + 1);
            }
        }
        for (const k in days)
            days[k].sort((a, b) => (b.allDay - a.allDay) || a.start - b.start);
        occurrences = all;
        byDay = days;
        revision++;
    }

    // A new day: the span moves and "today" changes.
    property string today: dayKey(clock.date)
    onTodayChanged: rebuild()
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ---- Fetching ------------------------------------------------------------------------------
    // A fingerprint of an address (to know the saved copy is still for it).
    function fingerprint(s) {
        let h = 5381;
        for (let i = 0; i < s.length; i++)
            h = ((h << 5) + h + s.charCodeAt(i)) | 0;
        return (h >>> 0).toString(16) + "-" + s.length;
    }

    function refresh() {
        if (!enabled)
            return;
        if (fetch.running) {
            fetch.again = true;
            return;
        }
        fetching = true;
        fetch.failures = [];
        fetch.fetchAt(0);
    }

    Process {
        id: fetch

        property int index: 0
        property var failures: []
        property bool again: false
        property string address: ""
        // Both have to arrive (in either order) before the next one starts.
        property bool streamDone: false
        property bool exitDone: false
        property bool parsed: false
        property int exitCode: 0

        function fetchAt(i) {
            index = i;
            address = root.sources[i];
            streamDone = exitDone = parsed = false;
            stdinEnabled = true;
            running = true;
        }
        function advance() {
            if (!streamDone || !exitDone)
                return;
            if (!parsed && !failures.includes(index))
                failures.push(index);
            const next = index + 1;
            if (next < root.sources.length)
                Qt.callLater(() => fetch.fetchAt(next));
            else
                Qt.callLater(done);
        }
        function done() {
            root.fetching = false;
            root.status = failures.length === 0 ? ""
                : root.sources.length === 1 ? "Can't fetch the calendar (offline, or a wrong address?)"
                : "Can't fetch calendar " + failures.map(i => i + 1).join(", ") + " (offline, or a wrong address?)";
            if (failures.length)
                console.log("events: " + root.status);
            root.save();
            root.rebuild();
            if (again) {
                again = false;
                root.refresh();
            }
        }

        // The address goes in on stdin (curl -K -), not on the command line.
        command: ["curl", "-fsSL", "--compressed", "--max-time", "30", "-K", "-"]
        onStarted: {
            write('url = "' + address.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"\n');
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const i = fetch.index;
                const cal = text.length > 0 ? Ics.parse(text) : null;
                if (cal) {
                    fetch.parsed = true;
                    cal.fp = root.fingerprint(fetch.address);
                    cal.fetchedAt = Date.now();
                    const list = root.calendars.slice();
                    list[i] = cal;
                    root.calendars = list;
                    const odd = Ics.unknownZones(cal);
                    console.log("events: calendar " + (i + 1) + ": " + cal.events.length + " events"
                        + (odd.length ? " (times in " + odd.join(", ") + " shown as local time)" : ""));
                }
                fetch.streamDone = true;
                fetch.advance();
            }
        }
        onExited: (code, status) => {
            exitCode = code;
            exitDone = true;
            advance();
        }
    }

    Timer {
        running: root.enabled
        repeat: true
        interval: Math.max(5, Style.calendarRefreshMinutes) * 60000
        onTriggered: root.refresh()
    }

    // Other addresses (Settings): forget the ones that went, fetch the new
    // (not before the saved copy is read: that fetches what's missing).
    onSourcesChanged: {
        if (!loaded)
            return;
        match();
        changed.restart();
    }
    Timer {
        id: changed
        interval: 600
        onTriggered: root.refresh()
    }

    // ---- The saved copy ------------------------------------------------------------------------
    property var saved: []
    property bool loaded: false
    // Saved calendars that belong to the current addresses, in their order.
    function match() {
        const list = sources.map(s => {
            const fp = fingerprint(s);
            return calendars.find(c => c && c.fp === fp) ?? saved.find(c => c && c.fp === fp) ?? null;
        });
        calendars = list;
        rebuild();
    }

    function save() {
        cache.setText(JSON.stringify({ version: 1, calendars: calendars.filter(c => c !== null) }));
    }

    FileView {
        id: cache
        path: root.cachePath
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                root.saved = JSON.parse(text()).calendars ?? [];
            } catch (e) {
                root.saved = [];
            }
            root.loaded = true;
            root.match();
            const old = Date.now() - Math.max(5, Style.calendarRefreshMinutes) * 60000;
            if (root.calendars.some(c => c === null || c.fetchedAt < old))
                root.refresh();
        }
        onLoadFailed: {
            root.loaded = true;
            root.match();
            root.refresh();
        }
    }

    Component.onCompleted: {
        const dir = cachePath.substring(0, cachePath.lastIndexOf("/"));
        Quickshell.execDetached(["mkdir", "-p", dir]);
    }
}
