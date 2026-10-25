pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.common
import "markup.js" as Markup

// The notification daemon: apps send their notifications here.
//
// Every notification becomes an entry in `list` (newest first), a plain copy
// we own, saved to ~/.local/state/mine-shell/notifications.json so the list
// survives reloads, restarts and logins. The live Notification object is
// only kept (in `live`) for its buttons, while the app still listens.
//
// Entry: { key, id, pid, time, appName, summary, body, icon, image,
//          urgency, actions: [{ identifier, text }], transient, resident,
//          popup (showing as a popup), read,
//          replyable (the app takes an answer typed in the card), replyHint,
//          count (how many times it came: repeats are counted on it),
//          first (when the first of them came; `time` is the latest) }
// A phone's notification (KDE Connect) is shown as its app's own: appName
// is the phone's app, summary the sender (see "Phone" below).
Singleton {
    id: root

    property var list: []
    // Goes up whenever an entry's content changes (cards re-read it).
    property int revision: 0
    property bool dnd: false
    property bool centerOpen: false
    // Quiet for another reason than Silent: a fullscreen window has focus
    // (Style.dndFullscreen). Like Silent, but on its own (Silent isn't
    // touched, so turning it on or off by hand still works as before).
    readonly property bool fullscreenQuiet: Style.dndFullscreen && Fullscreen.active
    readonly property bool privacyQuiet: Privacy.quiet    // the screen is shared (Privacy.qml); read from the start, so it's known in time

    readonly property var popups: list.filter(e => e.popup)
    // The bell's list, one group per app (or one per notification with
    // Style.notifGroupByApp off), in order of each one's newest:
    // [{ id, app, entries (newest first) }]
    readonly property var groups: {
        const out = [], at = {};
        for (const e of list) {
            const app = e.appName || "Notification";
            const id = Style.notifGroupByApp ? "app:" + app : e.key;
            if (at[id] === undefined) {
                at[id] = out.length;
                out.push({ id: id, app: app, entries: [] });
            }
            out[at[id]].entries.push(e);
        }
        return out;
    }
    // The popup whose reply field is open ("" = none): the popup window
    // takes the keyboard meanwhile, and it doesn't time out.
    property string replying: ""
    readonly property int unread: list.filter(e => !e.read).length
    readonly property date now: clock.date

    // Popups window: exists while there are popups, plus their exit animation.
    property bool popupsMapped: false
    // List panel: exists while open, plus its exit animation.
    property bool centerMapped: false

    property var live: ({})
    property int counter: 0
    property bool loaded: false

    // MINE_NOTIF_HISTORY / MINE_NOTIF_SOUND=0 are for testing.
    readonly property string historyPath: Quickshell.env("MINE_NOTIF_HISTORY")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/notifications.json")
    readonly property bool sound: Style.notifSound && Quickshell.env("MINE_NOTIF_SOUND") !== "0"

    // ---- What the cards and buttons call ---------------------------------------

    // Close for good: gone from the list, and the app is told.
    function dismiss(key) {
        const n = live[key];
        delete live[key];
        list = list.filter(e => e.key !== key);
        n?.dismiss();
        save();
    }

    // Stop showing as a popup; it stays in the list (unless it's transient).
    function hidePopup(key) {
        const e = find(key);
        if (!e || !e.popup)
            return;
        if (e.transient) {
            dismiss(key);
            return;
        }
        e.popup = false;
        list = list.slice();
        save();
    }

    // Click on a card: the app's default action if it has one.
    function activate(key) {
        const e = find(key);
        if (e && e.actions.some(a => a.identifier === "default"))
            invoke(key, "default");
        else
            hidePopup(key);
    }

    function invoke(key, identifier) {
        const e = find(key);
        const action = live[key]?.actions.find(a => a.identifier === identifier);
        action?.invoke();
        if (e && e.resident)
            hidePopup(key);
        else
            dismiss(key);
    }

    // Send the text typed in a card's reply field (inline reply). Like a
    // button, it's done after that (unless the app keeps it around).
    function reply(key, text) {
        const n = live[key];
        if (replying === key)
            replying = "";
        if (!n || text.trim() === "")
            return;
        n.sendInlineReply(text);
        const e = find(key);
        if (e && e.resident)
            hidePopup(key);
        else
            dismiss(key);
    }

    // Everything from one app (a group in the list).
    function dismissApp(app) {
        const gone = list.filter(e => (e.appName || "Notification") === app);
        for (const e of gone) {
            live[e.key]?.dismiss();
            delete live[e.key];
        }
        list = list.filter(e => (e.appName || "Notification") !== app);
        save();
    }

    function clearAll() {
        for (const key in live)
            live[key]?.dismiss();
        live = {};
        list = [];
        save();
    }

    function toggleDnd() {
        dnd = !dnd;
        save();
    }

    function setCenter(open) {
        if (open) {
            // Everything is on screen now: no popups, nothing unread.
            for (const e of list) {
                e.popup = false;
                e.read = true;
            }
            list = list.slice();
            centerUnmap.stop();
            centerMapped = true;
            save();
        } else {
            centerUnmap.restart();
        }
        centerOpen = open;
    }

    // "now", "5m", "2h", "Mon", "14 Oct".
    function ago(time) {
        const minutes = Math.floor((now.getTime() - time) / 60000);
        if (minutes < 1)
            return "now";
        if (minutes < 60)
            return minutes + "m";
        if (minutes < 24 * 60)
            return Math.floor(minutes / 60) + "h";
        const date = new Date(time);
        const locale = Style.clockLocale !== "" ? Qt.locale(Style.clockLocale) : Qt.locale();
        return locale.toString(date, minutes < 7 * 24 * 60 ? "ddd" : "d MMM");
    }

    // ---- Receiving --------------------------------------------------------------

    function find(key) {
        return list.find(e => e.key === key);
    }

    function receive(n) {
        n.tracked = true;
        // Same id while still live: the app replaced its notification.
        let e = list.find(x => x.pid === Quickshell.processId && x.id === n.id && live[x.key] !== undefined);
        const fresh = e === undefined;
        if (fresh)
            e = { key: Date.now() + "-" + (counter++), id: n.id, pid: Quickshell.processId, time: Date.now(), first: Date.now(), count: 1 };
        fill(e, n);
        // A muted app (Style.notifRules): not shown, not kept.
        if (ruleFor(appOf(e)) === "mute") {
            mute(e, n, fresh);
            return;
        }
        // The same again while the first is still in the list: counted on it.
        const first = fresh ? list.find(x => sameAs(x, e) && (fromPhone(n) !== null || Date.now() - x.time < repeatWindow)) : undefined;
        if (first !== undefined) {
            repeat(first, n);
            return;
        }
        e.read = centerOpen;
        // While the launcher, the clipboard, the calendar or the Now Playing
        // card is open it owns the middle island: straight to the list (the
        // System popup too, when it grew out of the middle island).
        e.popup = !centerOpen && !LauncherState.open && !ClipboardState.open && !CalendarState.open
                  && !NowPlayingState.open
                  && !(SysmonState.open && SysmonState.island === "center")
                  && ((!dnd && !fullscreenQuiet && !privacyQuiet) || e.urgency === NotificationUrgency.Critical);
        // "List only" (Style.notifRules): never a popup or sound, urgent or not.
        // The same for one the shell sends itself with x-mine-quiet, when a
        // live activity has already said it (a screenshot, a picked color).
        if (ruleFor(appOf(e)) === "quiet" || n.hints?.["x-mine-quiet"])
            e.popup = false;
        live[e.key] = n;
        watch(e, n);
        list = fresh ? [e].concat(list) : list.slice();
        // A transient one that didn't pop up (Do Not Disturb, a panel open):
        // in the list for a minute, then gone (transientSweep).
        if (e.transient && !e.popup)
            transientSweep.restart();
        revision++;
        limitPopups();
        trim();
        if (sound && e.popup && e.urgency !== NotificationUrgency.Low && !n.hints["suppress-sound"])
            Quickshell.execDetached(["canberra-gtk-play", "-i", "message-new-instant", "-d", "mine"]);
        save();
    }

    function fill(e, n) {
        // From the phone (KDE Connect): its app, the sender, the text.
        const phone = fromPhone(n);
        // KDE apps may name what they show for in a hint.
        e.appName = phone?.app ?? (n.hints?.["x-kde-display-appname"] || n.appName || "");
        e.summary = phone?.title ?? (n.summary || "");
        // Only a little markup: no pictures from the internet (markup.js).
        e.body = Markup.body(phone?.body ?? (n.body || ""));
        e.urgency = n.urgency;
        // Quickshell hands an app icon (notify-send -i firefox) and an
        // image-path over as image://icon/...: a path there is a real
        // picture, a name is only the app's icon.
        const picture = n.image || "";
        let iconFromImage = "";
        if (picture.startsWith("image://icon/")) {
            const rest = picture.substring("image://icon/".length);
            e.image = rest.startsWith("/") ? "file://" + rest : "";
            iconFromImage = rest.startsWith("/") ? "" : picture;
        } else {
            e.image = imageSource(picture);
        }
        e.icon = (phone ? phoneIcon(phone.app) : "") || iconSource(n) || iconFromImage;
        e.actions = n.actions.map(a => ({ identifier: a.identifier, text: a.text }));
        e.transient = n.transient;
        e.resident = n.resident;
        e.timeout = n.expireTimeout;
        e.replyable = n.hasInlineReply;
        e.replyHint = n.inlineReplyPlaceholder || "";
    }

    // Keep the entry in step with its notification while it lives.
    function watch(e, n) {
        const update = () => {
            if (root.live[e.key] !== n)
                return;
            root.fill(e, n);
            root.revision++;
            root.save();
        };
        n.summaryChanged.connect(update);
        n.bodyChanged.connect(update);
        n.imageChanged.connect(update);
        n.appIconChanged.connect(update);
        n.actionsChanged.connect(update);
        n.hasInlineReplyChanged.connect(update);
        n.inlineReplyPlaceholderChanged.connect(update);
        n.closed.connect(reason => root.closed(e.key, n, reason));
    }

    function closed(key, n, reason) {
        if (live[key] !== n)
            return;
        delete live[key];
        // The app took it back (e.g. you read the message there), or a
        // transient one (a Wi-Fi password from a QR code…) is over: it was
        // only ever for the moment, never for the list.
        if (reason === NotificationCloseReason.CloseRequested || find(key)?.transient) {
            list = list.filter(e => e.key !== key);
        } else {
            const e = find(key);
            if (e) {
                e.actions = [];
                e.replyable = false;
                // Pictures sent as data only live as long as the notification.
                if (e.icon.startsWith("image://qsimage"))
                    e.icon = "";
                if (e.image.startsWith("image://qsimage"))
                    e.image = "";
                revision++;
            }
        }
        save();
    }

    // Bounded in memory too, not only on disk: at most notifHistoryMax
    // entries, and only the newest `liveMax` keep their notification (its
    // buttons and pictures). Older ones expire, as if they had timed out
    // (the app hears so), and stay in the list as text. Popups and
    // resident ones are left alone.
    readonly property int liveMax: 30
    function trim() {
        if (list.length > Style.notifHistoryMax) {
            const gone = list.slice(Style.notifHistoryMax);
            list = list.slice(0, Style.notifHistoryMax);
            for (const e of gone) {
                const n = live[e.key];
                delete live[e.key];
                n?.expire();
            }
        }
        let kept = 0;
        for (const e of list.slice()) {
            const n = live[e.key];
            if (!n || e.popup || e.resident)
                continue;
            if (++kept > liveMax)
                n.expire();      // closed() drops it from `live`
        }
    }

    function limitPopups() {
        const shown = list.filter(e => e.popup);
        if (shown.length <= Style.notifMaxPopups)
            return;
        for (const e of shown.slice(Style.notifMaxPopups)) {
            if (e.transient) {
                dismiss(e.key);
            } else {
                e.popup = false;
            }
        }
        list = list.slice();
    }

    // An icon name, a file, or the icon of the app's .desktop entry; "" if none.
    function iconSource(n) {
        const icon = n.appIcon || "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        if (icon.startsWith("file://") || icon.startsWith("image://"))
            return icon;
        const name = icon || DesktopEntries.byId(n.desktopEntry)?.icon || DesktopEntries.heuristicLookup(n.appName)?.icon || "";
        if (name.startsWith("/"))
            return "file://" + name;
        return name !== "" ? Quickshell.iconPath(name, true) : "";
    }

    function imageSource(image) {
        if (!image)
            return "";
        return image.startsWith("/") ? "file://" + image : image;
    }

    // The app an entry is listed (and grouped, and ruled) under.
    function appOf(e) {
        return e.appName || "Notification";
    }

    // ---- Phone (KDE Connect) ------------------------------------------------------
    // KDE Connect passes on the phone's notifications. It names the phone's
    // app in the hint x-kde-display-appname only if the server lists that
    // hint among its capabilities, which it asks once, when it starts (we do
    // list it: extraHints below). Otherwise the summary is the phone's app
    // and the body "Sender: text" (its own markup-escaped title, ": ", the
    // text). Either way: { app, title, body }; null if it isn't one.
    function fromPhone(n) {
        const hints = n.hints ?? {};
        // Its notifications plugin marks them with the phone; its own (pairing,
        // ping, battery…) aren't, and have other event ids.
        const passedOn = hints["x-kdeconnect-source-device"] !== undefined
            || (n.appName === "KDE Connect" && hints["x-kde-eventId"] === "notification");
        if (!passedOn)
            return null;
        const app = String(hints["x-kde-display-appname"] ?? "");
        if (app !== "")
            return { app: app, title: n.summary || "", body: n.body || "" };
        return splitPhone(n.summary || "", n.body || "");
    }

    // "Sender: text" -> the sender (as plain text) and the text. Without a
    // sender in front (KDE Connect leaves it out when there's no title) the
    // text stays whole; a text that has ": " of its own can't be told apart.
    function splitPhone(app, body) {
        const at = body.indexOf(": ");
        const head = at > 0 && at <= 80 ? body.substring(0, at) : "";
        if (head === "" || /<br|\n/i.test(head))
            return { app: app || "KDE Connect", title: "", body: body };
        return { app: app || "KDE Connect", title: plainText(head), body: body.substring(at + 2) };
    }

    function plainText(html) {
        return html.replace(/<[^<>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"").replace(/&#0*39;|&apos;/g, "'").replace(/&amp;/g, "&");
    }

    // The phone app's own icon, looked up once per app; "" = none (the card
    // keeps KDE Connect's). Papirus has most of them but isn't the shell's
    // icon theme, so its files come first (a file also shows on the lock
    // screen, which has no icon theme); then the theme.
    readonly property var phoneIconNames: ({
        "messenger": ["messengerfordesktop", "fbmessenger", "caprine"],
        "telegram": ["telegram", "telegram-desktop", "org.telegram.desktop"],
        "x": ["twitter-x", "twitter"],
        "messages": ["android-messages-desktop", "AndroidMessages"],
        "google chat": ["google-chat"],
        "whatsapp business": ["whatsapp"]
    })
    readonly property var papirusDirs: [
        Quickshell.env("HOME") + "/.local/share/icons/Papirus/64x64/apps/",
        "/usr/share/icons/Papirus/64x64/apps/"
    ]
    // (Without a prototype: an app may be called "constructor".)
    property var phoneIcons: Object.create(null)

    function phoneIcon(app) {
        if (phoneIcons[app] !== undefined)
            return phoneIcons[app];
        const key = app.toLowerCase().trim();
        // Only plain names: they become file names.
        const aliases = Object.prototype.hasOwnProperty.call(phoneIconNames, key) ? phoneIconNames[key] : [];
        const names = aliases.concat([key.replace(/\s+/g, "-"), key.replace(/\s+/g, "")])
            .filter(name => /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name));
        let found = "";
        for (const name of names) {
            for (const dir of papirusDirs) {
                if (found === "" && fileExists(dir + name + ".svg"))
                    found = "file://" + dir + name + ".svg";
            }
        }
        for (const name of names) {
            if (found === "")
                found = Quickshell.iconPath(name, true);
        }
        iconProbe.path = "";
        if (Object.keys(phoneIcons).length > 200)
            phoneIcons = Object.create(null);
        phoneIcons[app] = found;
        return found;
    }

    // Whether a file is there (read at once; only small icon files).
    FileView {
        id: iconProbe
        blockAllReads: true
        printErrors: false
    }
    function fileExists(path) {
        iconProbe.path = path;
        iconProbe.text();
        return iconProbe.loaded;
    }

    // ---- Repeats ----------------------------------------------------------------------
    // The same notification again (same app, title, text and picture) while
    // the first is still in the list: no second card, popup or sound. The
    // first counts it (×2), takes the new time and goes to the top. (A phone
    // sends again what's unread each time it reconnects, 3 in a second, or
    // hours later.) From an app on this computer only within repeatWindow:
    // later, the same words are a reminder ("Back to work", "Battery
    // charged") and show as a new one.
    readonly property int repeatWindow: 10 * 60 * 1000
    function sameAs(a, b) {
        // Pictures sent as data get a new address each time.
        const picture = s => (s ?? "").startsWith("image://qsimage") ? "" : (s ?? "");
        return appOf(a) === appOf(b) && a.summary === b.summary && a.body === b.body
            && picture(a.image) === picture(b.image);
    }

    function repeat(e, n) {
        const old = live[e.key];
        e.count = (e.count ?? 1) + 1;
        e.time = Date.now();
        e.id = n.id;
        e.pid = Quickshell.processId;
        if (centerOpen)
            e.read = true;
        fill(e, n);
        // The new one keeps the buttons working; the old one is let go
        // (after, so its closing doesn't touch the entry).
        live[e.key] = n;
        watch(e, n);
        old?.expire();
        list = [e].concat(list.filter(x => x !== e));
        revision++;
        trim();
        save();
    }

    // ---- Per-app rules (Style.notifRules) -------------------------------------------
    // Right-click a notification (or an app in the list):
    //   "mute"   not shown, not kept; the app hears it expired (as if it
    //            timed out, nothing more), and what's in the list goes too.
    //   "quiet"  "List only": into the list, no popup or sound.
    // Both hold for urgent ones too (Silent lets those through; a rule is
    // about one app you picked).
    // Through a string, so `rules` only changes when the rules do (Style's
    // knob is read again whenever any setting changes).
    readonly property string rulesText: JSON.stringify(Style.notifRules ?? {})
    // [{ app, rule }], by app name.
    readonly property var rules: {
        const out = [];
        try {
            const all = JSON.parse(rulesText);
            if (all && typeof all === "object" && !Array.isArray(all)) {
                for (const app of Object.keys(all).sort()) {
                    if (all[app] === "mute" || all[app] === "quiet")
                        out.push({ app: app, rule: all[app] });
                }
            }
        } catch (e) {}
        return out;
    }

    function ruleFor(app) {
        return rules.find(r => r.app === app)?.rule ?? "";
    }

    // rule: "mute", "quiet", or "" to take the app's rule away.
    function setRule(app, rule) {
        const next = Object.create(null);
        for (const r of rules) {
            if (r.app !== app)
                next[r.app] = r.rule;
        }
        if (rule === "mute" || rule === "quiet")
            next[app] = rule;
        if (Object.keys(next).length === 0)
            Settings.reset("notifRules");
        else
            Settings.set("notifRules", next);
        if (rule === "mute")
            forgetApp(app);
        else if (rule === "quiet")
            list.filter(e => appOf(e) === app && e.popup).forEach(e => hidePopup(e.key));
    }

    // A muted app's new one: let go at once (expired) and never listed.
    function mute(e, n, fresh) {
        if (!fresh) {
            delete live[e.key];
            list = list.filter(x => x !== e);
            save();
        }
        n.expire();
    }

    // A muted app's ones in the list go, quietly (they expire).
    function forgetApp(app) {
        const gone = list.filter(e => appOf(e) === app);
        list = list.filter(e => appOf(e) !== app);
        for (const e of gone) {
            const n = live[e.key];
            delete live[e.key];
            n?.expire();
        }
        save();
    }

    // The launcher, the clipboard or the calendar opening puts away whatever
    // is showing (still unread).
    function putAwayPopups() {
        for (const e of list)
            e.popup = false;
        list = list.slice();
    }
    Connections {
        target: LauncherState
        function onOpenChanged() {
            if (LauncherState.open)
                root.putAwayPopups();
        }
    }
    Connections {
        target: ClipboardState
        function onOpenChanged() {
            if (ClipboardState.open)
                root.putAwayPopups();
        }
    }
    Connections {
        target: CalendarState
        function onOpenChanged() {
            if (CalendarState.open)
                root.putAwayPopups();
        }
    }
    Connections {
        target: NowPlayingState
        function onOpenChanged() {
            if (NowPlayingState.open)
                root.putAwayPopups();
        }
    }

    onPopupsChanged: {
        if (replying !== "" && !popups.some(e => e.key === replying))
            replying = "";
        if (popups.length > 0) {
            popupsUnmap.stop();
            popupsMapped = true;
        } else {
            popupsUnmap.restart();
        }
    }

    // The island window goes once the island reports it's back in the bar
    // (islandSettled). This is only a safety net in case it never does.
    Timer {
        id: popupsUnmap
        interval: Motion.morphOut + 1500
        onTriggered: root.popupsMapped = false
    }

    function islandSettled() {
        if (popups.length > 0)
            return;
        popupsUnmap.stop();
        // The window goes a moment later, not in the very frame the island
        // starts fading back in: letting go of a window stalls the shell
        // for ~50 ms, which made that fade stutter.
        popupsRelease.restart();
    }
    Timer {
        id: popupsRelease
        interval: Motion.contentIn + 80
        onTriggered: if (root.popups.length === 0) root.popupsMapped = false
    }
    Timer {
        id: centerUnmap
        interval: Motion.normal
        onTriggered: root.centerMapped = false
    }

    // Transient notifications that never popped up go a minute after they
    // came (a popup one goes when its popup does, hidePopup()).
    readonly property int transientLife: 60000
    Timer {
        id: transientSweep
        interval: 5000
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (const e of root.list.filter(x => x.transient && !x.popup && now - x.time >= root.transientLife))
                root.dismiss(e.key);
            if (!root.list.some(x => x.transient && !x.popup))
                stop();
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    NotificationServer {
        id: server

        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true
        inlineReplySupported: Style.notifReply
        // KDE Connect then names the phone's app in a hint (see fromPhone).
        extraHints: ["x-kde-display-appname"]

        onNotification: n => root.receive(n)
    }

    // ---- Silent hours (Style.dndSchedule) ----------------------------------------
    // From Style.dndFrom to Style.dndTo (across midnight is fine) Silent turns
    // on, and at the end off again. Changing Silent by hand in between sticks
    // until the next of those two times.
    // Inside the hours or not at the last change (kept with the list, so a
    // restart doesn't undo a change by hand); undefined = schedule just on.
    property var dndHoursWere: undefined
    readonly property bool inDndHours: within(now.getHours() * 60 + now.getMinutes(),
                                              minutesOf(Style.dndFrom), minutesOf(Style.dndTo))
    onInDndHoursChanged: checkDndHours()

    // "22:00" / "7.30" -> minutes after midnight; -1 if it isn't a time.
    function minutesOf(text) {
        const m = /^\s*(\d{1,2})[:.h](\d{2})\s*$/.exec(text ?? "");
        return m && +m[1] < 24 && +m[2] < 60 ? +m[1] * 60 + +m[2] : -1;
    }
    // Whether `minute` is from `from` up to (not including) `to`.
    function within(minute, from, to) {
        if (from < 0 || to < 0 || from === to)
            return false;
        return from < to ? (minute >= from && minute < to) : (minute >= from || minute < to);
    }

    function checkDndHours() {
        if (!loaded || !Style.dndSchedule || inDndHours === dndHoursWere)
            return;
        // Just switched on: only turn Silent on (inside the hours), never off.
        if (dndHoursWere !== undefined || inDndHours)
            dnd = inDndHours;
        dndHoursWere = inDndHours;
        save();
    }

    Connections {
        target: Style
        function onDndScheduleChanged() {
            if (!Style.dndSchedule) {
                root.dndHoursWere = undefined;
                root.save();
            }
            root.checkDndHours();
        }
    }

    // ---- Saving -------------------------------------------------------------------

    function save() {
        if (loaded)
            saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 800
        onTriggered: {
            // Never a transient one: it says it isn't for keeping (a Wi-Fi
            // password from a QR code, a one-time code).
            const keep = root.list.filter(e => !e.transient).slice(0, Style.notifHistoryMax).map(e => ({
                key: e.key, id: e.id, pid: e.pid, time: e.time,
                appName: e.appName, summary: e.summary, body: e.body,
                // Pictures sent as data only live as long as the notification.
                icon: e.icon.startsWith("image://qsimage") ? "" : e.icon,
                image: e.image.startsWith("image://qsimage") ? "" : e.image,
                urgency: e.urgency, resident: e.resident, read: e.read, count: e.count ?? 1, first: e.first ?? e.time
            }));
            store.setText(JSON.stringify({ dnd: root.dnd, dndHoursWere: root.dndHoursWere, list: keep }, null, 1));
        }
    }

    FileView {
        id: store
        path: root.historyPath
        atomicWrites: true
        printErrors: false

        onLoaded: root.restore(text())
        onLoadFailed: root.restore("")
    }

    function restore(text) {
        let data = {};
        try {
            data = text ? JSON.parse(text) : {};
        } catch (e) {
            console.warn("notifications: can't read", historyPath);
        }
        if (!data || typeof data !== "object")
            data = {};
        const saved =(Array.isArray(data.list) ? data.list : []).filter(s => s && typeof s === "object" && !list.some(e => e.key === s.key)).map(s => {
            const e = Object.assign({
                appName: "", summary: "", body: "", icon: "", image: "", urgency: NotificationUrgency.Normal,
                resident: false, read: true
            }, s, { body: Markup.body(s.body ?? ""), popup: false, actions: [], transient: false, replyable: false, replyHint: "",
                    count: Math.max(1, Math.round(Number(s.count) || 1)), first: typeof s.first === "number" ? s.first : s.time });
            // Saved before phone notifications showed as their app's own
            // (no count then): the same split as when one comes in.
            if (s.count === undefined && e.appName === "KDE Connect") {
                const phone = splitPhone(e.summary, e.body);
                e.appName = phone.app;
                e.summary = phone.title;
                e.body = Markup.body(phone.body);
                e.icon = phoneIcon(phone.app) || e.icon;
            }
            return e;
        });
        list = list.concat(saved).slice(0, Style.notifHistoryMax);
        dnd = data.dnd ?? dnd;
        dndHoursWere = data.dndHoursWere;
        loaded = true;
        relink();
        checkDndHours();
    }

    // After a reload the server still has the live notifications: hook them
    // back to their entries so their buttons keep working.
    function relink() {
        for (const n of server.trackedNotifications.values) {
            const e = list.find(x => x.pid === Quickshell.processId && x.id === n.id);
            if (!e || live[e.key] !== undefined)
                continue;
            live[e.key] = n;
            fill(e, n);
            watch(e, n);
        }
        revision++;
    }

    Component.onCompleted: {
        const dir = historyPath.substring(0, historyPath.lastIndexOf("/"));
        Quickshell.execDetached(["mkdir", "-p", dir]);
    }
}
