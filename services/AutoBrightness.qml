pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Auto brightness: the screen follows the light around you and learns from
// you. Off by default (Style.autoBrightness: Settings → Power & locking →
// Auto brightness, the A next to the control center's brightness slider,
// `qs -c mine ipc call autobright on|off|toggle`).
//
// The sensor: `monitor-sensor --light` (iio-sensor-proxy; the ALS is the
// IIO device named "als") runs only while this is on and the screen is on,
// not dimmed and not locked. It runs with LC_ALL=C (in Vietnamese it prints
// "59,000000"); a comma is read as a decimal point anyway. Claiming the
// sensor takes a few seconds; the value "Has ambient light sensor" prints
// then is the proxy's last one (seen: 59 when the room read 0), so it isn't
// taken, and a "Light changed: 0" right after the claim can be bogus: a 0
// counts only after a real reading above 0 since the sensor started. With
// no reading, the brightness stays as it is ("Waiting for the light
// sensor"), also in a room so dark that it reads 0 from the start.
//
// Light to brightness: a curve over log lux (dark room 15-25 %, living
// room ~40 %, office ~50 %, daylight 100 %), kept between
// autoBrightnessMin and autoBrightnessMax (a brightness you set yourself
// outside them is learned as it is) and never under 5 %. The screen
// only changes when the light has stayed more than ×1.4 away from where it
// was at the last change every second for 3 s (brighter) or 6 s (darker),
// and the brightness would move 4 % or more; it then goes to the curve's
// value at the average light of those seconds. A flickering lamp, a
// passing shadow or a flash does nothing. A change glides over
// autoBrightnessGlide seconds in 1 % steps (brightnessctl has no fade); the
// brightness OSD stays quiet for it.
//
// OLED: the panel's own light may reach the sensor. While gliding and for
// 2 s after, the light isn't followed; if it moved the same way as the
// screen in that time, that much (at most what the screen's own change can
// explain: its light can't change more than the brightness did) is taken
// as the panel's own light and not acted on, so a change can't feed itself.
//
// Learning: when you change the brightness while this is on (the keys, the
// control center's slider, brightnessctl in a terminal: any change that is
// neither this one's own nor Idle's), the light when you start and the
// brightness you settle on (2 s after your last change) become a learned
// point (no light reading yet: nothing is learned), and the curve bends
// through it: the light nearby follows, darker light never gets a brighter
// screen than that, brighter light never a darker one; a newer point
// replaces one at about the same light. Then it leaves yours alone
// until the light halves or doubles, or autoBrightnessHold minutes pass.
// Kept in ~/.local/state/mine-shell/autobright.json (24 points at most);
// "Forget what it learned" in Settings (or `ipc call autobright forget`).
//
// Idle: nothing happens while Idle has the screen dimmed or off, nor while
// its own glide runs (dimming, coming back); its changes are never taken
// for yours. Coming back, Idle glides to the brightness from before; the
// sensor starts again then, and this takes over once it has a fresh
// reading (seconds later), so two glides never run at once.
//
// MINE_AUTOBRIGHT_DRYRUN=1 (tests): prints "autobright (dry run): …"
// instead of setting the brightness. MINE_AUTOBRIGHT_LUX_CMD: a command run
// with sh -c instead of monitor-sensor (same output). MINE_AUTOBRIGHT_STATE:
// another file instead of autobright.json. MINE_AUTOBRIGHT_DEBUG=1 logs
// every step.
Singleton {
    id: root

    readonly property bool enabled: Style.autoBrightness
    readonly property bool dryRun: Quickshell.env("MINE_AUTOBRIGHT_DRYRUN") === "1"
    readonly property bool debug: Quickshell.env("MINE_AUTOBRIGHT_DEBUG") === "1"
    readonly property string luxCommand: Quickshell.env("MINE_AUTOBRIGHT_LUX_CMD") ?? ""
    readonly property string statePath: Quickshell.env("MINE_AUTOBRIGHT_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/autobright.json")

    // Never darker than this, whatever the knobs or the curve say.
    readonly property real floor: 0.05
    readonly property real lowest: Math.max(floor, Math.min(Style.autoBrightnessMin, Style.autoBrightnessMax))
    readonly property real highest: Math.max(lowest, Math.min(1, Math.max(Style.autoBrightnessMin, Style.autoBrightnessMax)))

    // How it decides (see the top).
    readonly property real luxHysteresis: 0.15      // log10: the light must move ×1.4
    readonly property real deadband: 0.04           // and the brightness 4 %
    readonly property int brighterAfter: 3          // s it must hold
    readonly property int darkerAfter: 6

    function log(...args) {
        if (debug)
            console.log("autobright:", ...args);
    }

    function setOn(on) {
        if (on)
            Settings.set("autoBrightness", true);
        else
            Settings.reset("autoBrightness");
    }
    function toggle() {
        setOn(!enabled);
    }

    // ---- When it runs -------------------------------------------------------------
    // The lock screen is up: lock.qml's marker, as Idle reads it (watched
    // here only while this is on; Idle watches it only for its own knobs).
    readonly property string marker: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-lock.secure"
    property bool markerThere: false
    readonly property bool locked: enabled && markerFile.path !== "" && markerThere

    FileView {
        id: markerFile
        path: root.enabled ? root.marker : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.markerThere = true
        onLoadFailed: root.markerThere = false
    }

    // The sensor is read while the screen is on, not dimmed, not locked.
    readonly property bool listening: enabled && !locked && !Idle.dimOn && !Idle.off
    // Idle is dimming, has dimmed, or glides back (also its restore after a
    // restart): its business.
    readonly property bool idleBusy: Idle.quietBrightness || Idle.dimOn || Idle.off || Idle.before >= 0
    readonly property bool paused: !listening || idleBusy || !Brightness.ready

    onEnabledChanged: {
        log("on", enabled);
        actedX = NaN;
        endHold("turned " + (enabled ? "on" : "off"));
        learnLater.stop();
        if (!enabled)
            glider.stop();
    }
    onListeningChanged: {
        log(listening ? "sensor on" : "sensor off");
        lux = -1;
        recent = [];
        smoothX = -1;
        streak = [];
    }
    onPausedChanged: {
        streak = [];
        if (paused && glider.running) {
            // Not where it was going: look again afterwards, even if the
            // light stays the same.
            log("paused in the middle of a glide; stopped");
            glider.stop();
            quietTail.restart();
            actedX = NaN;
        }
    }
    // New limits: look again even if the light hasn't moved.
    onLowestChanged: actedX = NaN
    onHighestChanged: actedX = NaN

    // ---- The sensor -----------------------------------------------------------------
    // Last reading taken (lux); -1 = none (not running, or not yet).
    property real lux: -1
    property bool sensorFound: true
    // It stopped by itself: tried again after a pause.
    property bool sensorResting: false

    Process {
        id: sensor
        running: root.listening && !root.sensorResting
        command: root.luxCommand !== "" ? ["sh", "-c", root.luxCommand] : ["monitor-sensor", "--light"]
        environment: ({ LC_ALL: "C" })
        stdout: SplitParser {
            onRead: line => root.heard(line)
        }
        onExited: (code, status) => {
            if (root.listening && !root.sensorResting) {
                console.warn("autobright: monitor-sensor stopped (exit " + code + "); trying again in 10 s");
                root.sensorResting = true;
                rest.restart();
            }
        }
    }
    Timer {
        id: rest
        interval: 10000
        onTriggered: root.sensorResting = false
    }

    function number(s) {
        return parseFloat(s.replace(",", "."));
    }

    // "=== Has ambient light sensor (value: 59.000000, unit: lux)",
    // "    Light changed: 59.000000 (lux)", "=== No ambient light sensor",
    // "+++ Light sensor appeared", "--- Light sensor disappeared",
    // "--- iio-sensor-proxy vanished, waiting for it to appear".
    function heard(line) {
        const has = /Has ambient light sensor \(value: ([0-9]+(?:[.,][0-9]+)?)/.exec(line);
        const changed = /Light changed: ([0-9]+(?:[.,][0-9]+)?)/.exec(line);
        if (has) {
            sensorFound = true;
            log("sensor claimed; its first value (" + number(has[1]) + " lux) can be old: not taken");
        } else if (changed) {
            const v = number(changed[1]);
            if (isNaN(v))
                return;
            if (lux < 0 && v <= 0)
                log("0 lux before any real reading: not taken");
            else
                take(v);
        } else if (/No ambient light sensor|Light sensor disappeared|Failed to claim light/.test(line)) {
            sensorFound = false;
            lux = -1;
        } else if (/iio-sensor-proxy vanished/.test(line)) {
            lux = -1;
        } else if (/Light sensor appeared/.test(line)) {
            sensorFound = true;
        }
    }

    function take(v) {
        if (lux !== v)
            log("light", v, "lux");
        lux = v;
        if (recent.length === 0)
            remember(xOf(v));
    }

    // ---- Following the light ----------------------------------------------------------
    // The light on a log scale: x = log10(1 + lux): 0 dark, 1 ≈ 10 lux,
    // 2 ≈ 100, 3 ≈ 1000, 4 ≈ 10000.
    function xOf(l) {
        return Math.log10(1 + Math.max(0, l));
    }
    function luxOf(x) {
        return Math.pow(10, x) - 1;
    }

    // The light of the last 5 s (x, one a second) and their median (-1 =
    // none yet): for the hold and what Settings shows.
    property var recent: []
    property real smoothX: -1
    function remember(x) {
        recent = recent.concat([x]).slice(-5);
        const sorted = recent.slice().sort((a, b) => a - b);
        smoothX = sorted[Math.floor(sorted.length / 2)];
    }
    // Where the light was (x) at the last change: it must move
    // luxHysteresis from there.
    property real actedX: NaN
    // The seconds in a row (x each) that wanted the same change, and which way.
    property var streak: []
    property int streakDir: 0
    // The light (x) when the last glide started, and the most the panel's
    // own light can have moved it by that glide (log10 of the brightness
    // ratio, signed: its light can't change more than the screen did).
    property real xBefore: NaN
    property real ownBound: 0
    // The light taken as the panel's own after the last glide (log10; status).
    property real ownLight: 0

    readonly property real target: smoothX >= 0 ? targetAt(smoothX) : -1

    Timer {
        id: tick
        interval: 1000
        repeat: true
        running: root.listening && root.lux >= 0
        onTriggered: root.step()
    }

    // Once a second. A change needs the light itself (not only its
    // average) away from where it was at the last change, every second of
    // the wait, all wanting the same way: a flash shorter than that, or a
    // light flickering across, never adds up. The new brightness is the
    // curve's at the average light of those seconds.
    function step() {
        // Our own glide (or your change) and a moment after: the panel may
        // light the sensor, so the light isn't followed.
        if (glider.running || blind.running) {
            streak = [];
            return;
        }
        const x = xOf(lux);
        remember(x);
        if (holding) {
            if (isNaN(holdX))
                holdX = x;
            else if (Math.abs(x - holdX) >= Math.log10(2) && Math.abs(smoothX - holdX) >= Math.log10(2))
                endHold("the light " + (smoothX > holdX ? "doubled" : "halved"));
        }
        if (paused || holding) {
            streak = [];
            return;
        }
        const diff = targetAt(x) - level();
        const dir = diff > 0 ? 1 : -1;
        const moved = isNaN(actedX) || Math.abs(x - actedX) >= luxHysteresis;
        if (!moved || Math.abs(diff) < deadband) {
            streak = [];
            return;
        }
        streak = (streakDir === dir ? streak : []).concat([x]);
        streakDir = dir;
        const need = dir > 0 ? brighterAfter : darkerAfter;
        log("wants", targetAt(x).toFixed(2), "at", Math.round(lux), "lux,", streak.length + "/" + need);
        if (streak.length < need)
            return;
        const mean = streak.reduce((a, b) => a + b, 0) / streak.length;
        streak = [];
        const goal = targetAt(mean);
        if (Math.abs(goal - level()) < deadband)
            return;
        actedX = mean;
        xBefore = x;
        ownBound = Math.log10(Math.max(floor, goal) / Math.max(floor, level()));
        glide(goal);
    }

    // After a glide: did the light move with the screen? Then that much,
    // up to ownBound, is the panel's own light (or can't be told from it):
    // not followed. The rest is the room's.
    Timer {
        id: blind
        interval: 2000
        property bool afterGlide: false
        onTriggered: {
            if (afterGlide)
                root.checkOwnLight();
        }
    }
    function checkOwnLight() {
        if (lux < 0 || smoothX < 0 || isNaN(xBefore))
            return;
        const drift = xOf(lux) - xBefore;
        ownLight = drift * ownBound > 0 && Math.abs(drift) > 0.02
            ? Math.sign(drift) * Math.min(Math.abs(drift), Math.abs(ownBound)) : 0;
        if (ownLight === 0)
            return;
        log("the light moved", drift.toFixed(2), "with the screen:", ownLight.toFixed(2), "of it taken as its own light");
        if (!isNaN(actedX))
            actedX += ownLight;
    }

    // ---- Gliding ----------------------------------------------------------------------
    // The brightness now (the dry run's own idea of it, as nothing is set).
    property real virtual: -1
    function level() {
        return dryRun && virtual >= 0 ? virtual : Brightness.value;
    }

    property real glideFrom: 0
    property real glideTo: 0
    property int glideStep: 0
    property int glideSteps: 1
    property int lastPercent: -1

    // True while gliding (and a moment after, for the last change to come
    // back from sysfs), so the brightness OSD doesn't pop up for it.
    readonly property bool quietBrightness: glider.running || quietTail.running

    function glide(to) {
        glideFrom = level();
        glideTo = to;
        glideStep = 0;
        glideSteps = Math.max(2, Math.min(30, Math.round(Math.abs(to - glideFrom) * 100)));
        glider.interval = Math.max(60, Math.round(Style.autoBrightnessGlide * 1000 / glideSteps));
        lastPercent = Math.round(glideFrom * 100);
        console.log("autobright:", Math.round(lux) + " lux, " + Math.round(glideFrom * 100) + "% → " + Math.round(to * 100) + "%");
        blind.stop();
        quietTail.stop();
        glider.restart();
    }
    Timer {
        id: glider
        repeat: true
        onTriggered: {
            root.glideStep++;
            const t = root.glideStep / root.glideSteps;
            root.write(root.glideFrom + (root.glideTo - root.glideFrom) * t * t * (3 - 2 * t));
            if (root.glideStep >= root.glideSteps) {
                stop();
                quietTail.restart();
                blind.afterGlide = true;
                blind.restart();
            }
        }
    }
    Timer {
        id: quietTail
        interval: 800
    }

    // Our own writes of the last few seconds: when they come back from
    // sysfs, they are ours, not yours.
    property var mine: []
    // Every brightness it sets (also in the dry run: tests echo it back).
    signal wrote(real value)
    function write(v) {
        const percent = Math.round(Math.max(floor, Math.min(1, v)) * 100);
        if (percent === lastPercent)
            return;
        lastPercent = percent;
        const f = percent / 100;
        const now = Date.now();
        mine = mine.filter(w => now - w.t < 3000).concat([{ f: f, t: now }]);
        virtual = f;
        if (dryRun)
            console.log("autobright (dry run): brightness", f.toFixed(2));
        else
            Brightness.set(f);
        wrote(f);
    }
    function ours(value) {
        const now = Date.now();
        return mine.some(w => now - w.t < 3000 && Math.abs(w.f - value) < 0.006);
    }

    // ---- Your changes -------------------------------------------------------------------
    property int lastRaw: -1
    Connections {
        target: Brightness
        function onRawChanged() {
            root.brightnessChanged();
        }
    }
    function brightnessChanged() {
        const prev = lastRaw;
        lastRaw = Brightness.raw;
        // From raw itself: Brightness.value may not have caught up yet here.
        if (!enabled || Brightness.max <= 0 || prev < 0 || Brightness.raw < 0 || Brightness.raw === prev)
            return;
        const v = Brightness.raw / Brightness.max;
        if (ours(v))
            return;
        if (idleBusy) {
            log("Idle's change to", v.toFixed(2));
            return;
        }
        yours(v);
    }

    // The keys and the control center's slider call this just before they
    // change it: the glide stops at once, so it can't step over yours. It
    // counts even when the brightness doesn't change (up at 100 %).
    function userSet() {
        if (!enabled)
            return;
        if (glider.running)
            log("your change stops the glide");
        glider.stop();
        quietTail.stop();
        mine = [];
        startHold();
        learnLater.restart();
    }

    // The light when you started changing it (not after: the screen's own
    // light, and you react to the room as it is now, not to the average).
    property real learnLux: -1

    function yours(v) {
        glider.stop();
        quietTail.stop();
        streak = [];
        virtual = v;
        log("your change to", v.toFixed(2));
        // Its own light isn't followed for a moment either.
        blind.afterGlide = false;
        blind.restart();
        startHold();
        learnLater.restart();
    }

    property bool holding: false
    property real holdX: NaN
    function startHold() {
        if (!learnLater.running) {
            learnLux = listening ? lux : -1;
            holdX = learnLux >= 0 ? xOf(learnLux) : NaN;
        }
        holding = true;
        holdTimer.restart();
    }
    function endHold(why) {
        if (!holding)
            return;
        holding = false;
        holdTimer.stop();
        log("following the light again:", why);
    }
    Timer {
        id: holdTimer
        interval: Math.max(1000, Style.autoBrightnessHold * 60000)
        onTriggered: root.endHold(Style.autoBrightnessHold + " min passed")
    }

    // The brightness you settled on, with the light then.
    Timer {
        id: learnLater
        interval: 2000
        onTriggered: root.learn()
    }
    function learn() {
        if (!enabled)
            return;
        if (!listening || learnLux < 0) {
            log("no light reading: your brightness is kept, not learned");
            return;
        }
        addPoint(learnLux, level());
        actedX = xOf(learnLux);
        holdX = actedX;
    }

    // ---- The curve ---------------------------------------------------------------------
    // Before anything is learned: [x, brightness] (x as above).
    readonly property var usual: [[0, 0.15], [0.5, 0.18], [1, 0.24], [1.5, 0.31], [2, 0.39],
                                  [2.5, 0.5], [3, 0.68], [3.5, 0.88], [4, 1], [4.5, 1]]
    // Learned: [{ lux, b, t }], oldest first.
    property var points: []
    readonly property var curve: build(points, lowest, highest)

    function valueAt(nodes, x) {
        if (x <= nodes[0].x)
            return nodes[0].b;
        for (let i = 1; i < nodes.length; i++) {
            if (x <= nodes[i].x) {
                const a = nodes[i - 1];
                const c = nodes[i];
                return a.b + (c.b - a.b) * (x - a.x) / (c.x - a.x);
            }
        }
        return nodes[nodes.length - 1].b;
    }

    // The usual curve kept between the knobs (lo, hi), then each learned
    // point in turn (the newest last, so it wins; yours may be outside the
    // knobs): the curve goes through it, the light nearby follows (half as
    // much about ×2.6 away), and it stays monotone around it: darker light
    // no brighter than it, brighter light no darker.
    function build(list, lo, hi) {
        let nodes = usual.map(k => ({ x: k[0], b: Math.max(lo, Math.min(hi, k[1])) }));
        for (const p of list) {
            const x = xOf(p.lux);
            const e = p.b - valueAt(nodes, x);
            nodes = nodes.filter(n => Math.abs(n.x - x) > 0.05)
                         .map(n => ({ x: n.x, b: n.b + e * Math.exp(-Math.pow((n.x - x) / 0.5, 2)) }));
            nodes.push({ x: x, b: p.b });
            nodes.sort((a, c) => a.x - c.x);
            const at = nodes.findIndex(n => n.x === x);
            for (let i = at - 1; i >= 0; i--)
                nodes[i].b = Math.min(nodes[i].b, nodes[i + 1].b);
            for (let i = at + 1; i < nodes.length; i++)
                nodes[i].b = Math.max(nodes[i].b, nodes[i - 1].b);
            for (const n of nodes)
                n.b = Math.max(0.01, Math.min(1, n.b));
        }
        return nodes;
    }

    function targetAt(x) {
        return Math.max(floor, Math.min(1, valueAt(curve, x)));
    }

    function addPoint(l, b) {
        const x = xOf(l);
        let list = points.filter(p => Math.abs(xOf(p.lux) - x) >= 0.2);
        list.push({ lux: Math.round(l * 10) / 10, b: Math.round(b * 100) / 100, t: Date.now() });
        if (list.length > 24)
            list = list.slice(list.length - 24);
        points = list;
        save();
        console.log("autobright: learned " + Math.round(l) + " lux → " + Math.round(b * 100) + "% (" + list.length + " learned)");
    }

    function forget() {
        points = [];
        save();
        actedX = NaN;
        console.log("autobright: forgot what it learned");
    }

    // ---- Kept across restarts -------------------------------------------------------------
    function save() {
        stateFile.setText(JSON.stringify({ points: points }, null, 1) + "\n");
    }
    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text() || "{}");
                root.points = (saved.points ?? []).filter(p => typeof p.lux === "number" && typeof p.b === "number"
                    && p.lux >= 0 && p.b > 0 && p.b <= 1);
            } catch (e) {
                console.warn("autobright: can't read", root.statePath, "- starting from the usual curve");
            }
        }
    }

    // ---- Saying how it goes ----------------------------------------------------------------
    readonly property string why: !enabled ? "off"
        : locked ? "locked"
        : Idle.off ? "screen off"
        : Idle.dimOn ? "dimmed"
        : idleBusy ? "idle's glide"
        : !Brightness.ready ? "no backlight"
        : !sensorFound ? "no light sensor"
        : lux < 0 ? "waiting for the light sensor"
        : holding ? "keeping your brightness"
        : ""

    // One line for Settings.
    readonly property string info: !enabled ? "Off"
        : !sensorFound ? "No light sensor found (iio-sensor-proxy)"
        : locked ? "Paused while locked"
        : Idle.dimOn || Idle.off ? "Paused while the screen is dimmed or off"
        : lux < 0 ? "Waiting for the light sensor"
        : Math.round(lux) + " lux · aiming for " + Math.round(target * 100) + "%"
          + (holding ? " · keeping yours for now" : "")
    readonly property string learnedText: points.length === 0 ? "Nothing learned yet"
        : points.length === 1 ? "1 brightness learned" : points.length + " brightnesses learned"

    // For `qs -c mine ipc call autobright status`.
    function status() {
        return JSON.stringify({
            on: enabled, listening: sensor.running, paused: paused, why: why, sensorFound: sensorFound,
            lux: lux >= 0 ? Math.round(lux * 10) / 10 : null,
            smoothLux: smoothX >= 0 ? Math.round(luxOf(smoothX) * 10) / 10 : null,
            target: target >= 0 ? Math.round(target * 100) / 100 : null,
            brightness: Brightness.ready ? Math.round(level() * 100) / 100 : null,
            gliding: glider.running, holding: holding, dryRun: dryRun,
            learned: points.map(p => ({ lux: p.lux, brightness: p.b }))
        });
    }
}
