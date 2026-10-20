pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The weather for the calendar card, from Open-Meteo (free, no key) for
// Style.weatherCity (lat/lon in Style). Fetched with curl when the shell
// starts (if the saved copy is older than Style.weatherRefreshMinutes) and
// then every Style.weatherRefreshMinutes, only while the shell runs. The last
// answer is kept in ~/.local/state/mine-shell/weather.json, so the card shows
// it at once at start, and also when you're offline (with its age).
//
// The place can be changed by name (Settings window): findPlace() asks
// Open-Meteo's geocoding for it and sets the city, latitude and longitude
// together; a new place is fetched right away.
//
// The lock screen (lock.qml sets MINE_WEATHER_READONLY=1) only reads the
// saved copy, which the shell keeps fresh, and follows it when it changes;
// it fetches once only if there is no copy for this place or it's very old.
//
// Tests: MINE_WEATHER_CACHE (where the copy goes), MINE_WEATHER_URL (instead
// of Open-Meteo, e.g. an unreachable address to act offline),
// MINE_GEOCODE_URL (instead of the geocoding address; the name is added).
Singleton {
    id: root

    readonly property bool enabled: Style.weatherEnabled
    readonly property bool readOnly: Quickshell.env("MINE_WEATHER_READONLY") === "1"
    readonly property string cachePath: Quickshell.env("MINE_WEATHER_CACHE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/weather.json")
    readonly property string url: Quickshell.env("MINE_WEATHER_URL")
        || ("https://api.open-meteo.com/v1/forecast?latitude=" + Style.weatherLatitude
            + "&longitude=" + Style.weatherLongitude
            + "&current=temperature_2m,weather_code,is_day"
            + "&hourly=temperature_2m,weather_code,is_day"
            + "&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset"
            + "&timezone=auto&forecast_days=2")

    // Open-Meteo's answer plus { fetchedAt } (ms), or null before the first.
    property var data: null
    property bool fetching: false
    property bool failed: false            // the last try didn't work (offline?)
    readonly property bool ready: data !== null
    readonly property date now: clock.date

    // ---- What the card shows --------------------------------------------------------
    readonly property real temperature: data?.current?.temperature_2m ?? 0
    readonly property int code: data?.current?.weather_code ?? 0
    readonly property bool isDay: (data?.current?.is_day ?? 1) === 1
    readonly property real high: data?.daily?.temperature_2m_max?.[0] ?? 0
    readonly property real low: data?.daily?.temperature_2m_min?.[0] ?? 0
    // Minutes since it was fetched (the card says "2h ago" when it's old).
    readonly property int ageMinutes: data ? Math.max(0, Math.round((now.getTime() - data.fetchedAt) / 60000)) : 0

    // Today's sunrise and sunset at the place, as { rise, set } in ms (for
    // Theme's "auto"), or null before the weather (or an older copy) has them.
    // Open-Meteo gives the place's local time ("2026-10-15T05:43") and its
    // offset from UTC.
    function sunTimes() {
        const d = data?.daily;
        if (!d?.sunrise || !d?.sunset)
            return null;
        const offset = (data.utc_offset_seconds ?? 0) * 1000;
        const today = new Date(Date.now() + offset).toISOString().substring(0, 10);
        const i = Math.max(0, (d.time ?? []).indexOf(today));
        const ms = t => {
            const m = /^(\d+)-(\d+)-(\d+)T(\d+):(\d+)/.exec(t ?? "");
            return m ? Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]) - offset : NaN;
        };
        const rise = ms(d.sunrise[i]), set = ms(d.sunset[i]);
        return isNaN(rise) || isNaN(set) ? null : { rise: rise, set: set };
    }

    // The next few hours from now: [{ hour: "14:00", temp, code, isDay }].
    function nextHours(count) {
        const h = data?.hourly;
        if (!h)
            return [];
        const out = [];
        const nowMs = now.getTime();
        for (let i = 0; i < h.time.length && out.length < count; i++) {
            // "2026-10-15T14:00", local time (timezone=auto).
            const t = new Date(h.time[i]).getTime();
            if (t + 3600000 <= nowMs)
                continue;
            out.push({ hour: h.time[i].substring(11, 16), temp: h.temperature_2m[i], code: h.weather_code[i], isDay: h.is_day[i] === 1 });
        }
        return out;
    }

    // WMO weather code → Material Symbols icon / words.
    function icon(code, day) {
        if (code === 0)
            return day ? "sunny" : "clear_night";
        if (code <= 2)
            return day ? "partly_cloudy_day" : "partly_cloudy_night";
        if (code === 3)
            return "cloud";
        if (code === 45 || code === 48)
            return "foggy";
        if (code >= 51 && code <= 57)
            return "rainy_light";
        if ((code >= 61 && code <= 67) || code === 80 || code === 81)
            return "rainy";
        if (code === 82)
            return "rainy_heavy";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86)
            return "weather_snowy";
        if (code >= 95)
            return "thunderstorm";
        return "cloud";
    }
    function words(code) {
        if (code === 0)
            return "Clear";
        if (code === 1)
            return "Mostly clear";
        if (code === 2)
            return "Partly cloudy";
        if (code === 3)
            return "Cloudy";
        if (code === 45 || code === 48)
            return "Fog";
        if (code >= 51 && code <= 57)
            return "Drizzle";
        if (code >= 61 && code <= 67)
            return "Rain";
        if (code >= 71 && code <= 77)
            return "Snow";
        if (code >= 80 && code <= 82)
            return "Showers";
        if (code === 85 || code === 86)
            return "Snow showers";
        if (code >= 95)
            return "Thunderstorm";
        return "";
    }

    // At start; the read-only lock screen fetches at most once.
    property bool triedOnce: false
    function refreshOnce() {
        if (readOnly && triedOnce)
            return;
        triedOnce = true;
        refresh();
    }

    function refresh() {
        if (!enabled)
            return;
        if (fetch.running) {
            fetch.again = true;
            return;
        }
        fetching = true;
        fetch.running = true;
    }

    // The saved answer is for this place (Open-Meteo snaps to its grid).
    function samePlace(d) {
        return Math.abs((d?.latitude ?? 999) - Style.weatherLatitude) < 0.25
            && Math.abs((d?.longitude ?? 999) - Style.weatherLongitude) < 0.25;
    }

    // A new place: fetch for it (once, after the last of lat/lon changed).
    Connections {
        target: Style
        function onWeatherLatitudeChanged() { moved.restart(); }
        function onWeatherLongitudeChanged() { moved.restart(); }
    }
    Timer {
        id: moved
        interval: 400
        onTriggered: root.refresh()
    }

    // ---- Changing the place by name ---------------------------------------------------
    // "" while idle; "Looking…", "Not found", "Can't reach Open-Meteo"
    // (those two go away after a few seconds).
    property string placeStatus: ""
    onPlaceStatusChanged: {
        if (placeStatus !== "" && placeStatus !== "Looking…")
            statusClear.restart();
    }
    Timer {
        id: statusClear
        interval: 5000
        onTriggered: root.placeStatus = ""
    }

    function findPlace(name) {
        const wanted = name.trim();
        if (wanted === "") {
            // Empty: back to the place in Style.qml.
            Settings.reset("weatherCity");
            Settings.reset("weatherLatitude");
            Settings.reset("weatherLongitude");
            placeStatus = "";
            return;
        }
        placeStatus = "Looking…";
        geocode.command = ["curl", "-fsS", "--max-time", "10",
            (Quickshell.env("MINE_GEOCODE_URL") || "https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name=")
            + encodeURIComponent(wanted)];
        geocode.running = true;
    }

    Process {
        id: geocode
        stdout: StdioCollector {
            onStreamFinished: {
                let place = null;
                try {
                    place = JSON.parse(text).results?.[0] ?? null;
                } catch (e) {}
                if (!place) {
                    root.placeStatus = "Not found";
                    return;
                }
                root.placeStatus = "";
                Settings.set("weatherCity", place.name);
                Settings.set("weatherLatitude", Math.round(place.latitude * 100) / 100);
                Settings.set("weatherLongitude", Math.round(place.longitude * 100) / 100);
            }
        }
        onExited: (code, status) => {
            if (code !== 0)
                root.placeStatus = "Can't reach Open-Meteo";
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Process {
        id: fetch
        // The place changed while fetching: fetch again after.
        property bool again: false
        command: ["curl", "-fsS", "--max-time", "15", root.url]
        onRunningChanged: {
            if (!running && again) {
                again = false;
                root.refresh();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let answer = null;
                try {
                    answer = JSON.parse(text);
                } catch (e) {}
                root.fetching = false;
                if (!answer?.current) {
                    root.failed = true;
                    return;
                }
                answer.fetchedAt = Date.now();
                root.data = answer;
                root.failed = false;
                cache.setText(JSON.stringify(answer));
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.fetching = false;
                root.failed = true;
            }
        }
    }

    Timer {
        running: root.enabled && !root.readOnly
        repeat: true
        interval: Math.max(5, Style.weatherRefreshMinutes) * 60000
        onTriggered: root.refresh()
    }

    // The saved copy: shown right away; fetch again only if it's old.
    FileView {
        id: cache
        path: root.cachePath
        atomicWrites: true
        printErrors: false
        watchChanges: root.readOnly

        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(text());
            } catch (e) {}
            // Read-only: only when there's nothing usable (3 h old or more).
            const maxAge = (root.readOnly ? 180 : Style.weatherRefreshMinutes) * 60000;
            if (!root.data || !root.samePlace(root.data) || Date.now() - root.data.fetchedAt > maxAge)
                root.refreshOnce();
        }
        onLoadFailed: root.refreshOnce()
    }

    Component.onCompleted: {
        const dir = cachePath.substring(0, cachePath.lastIndexOf("/"));
        Quickshell.execDetached(["mkdir", "-p", dir]);
    }
}
