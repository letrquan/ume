pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "qr.js" as Qr
import "translate.js" as Lang

// Screenshots.
//   region / window: freeze the focused screen first (grim the whole output),
//     then show it in the overlay (screenshot/ShotWindow.qml) where you drag a
//     region or click a window; the picture is cut out of the frozen image,
//     so nothing that moves after the key press ends up in it.
//   screen: the whole focused screen at once, no overlay.
// Then: saved to Style.screenshotDir, copied to the clipboard, and a
// notification with the picture (scripts/shot-notify.sh: click opens it,
// Edit, Delete).
//
// Edit switched on in the overlay (Style.screenshotEditor "markup"): once
// picked, the overlay stays and you draw on the pick (screenshot/
// MarkupLayer.qml); Save then saves, copies and notifies as above, Copy
// only copies (no file). With no marks Save is the plain cut, unchanged;
// with marks scripts/shot-mark.sh blurs and lays the drawn marks on the
// cut. The notification's Edit (editSaved(), IPC `screenshot edit <file>`)
// opens the same on a saved picture and saving writes it over.
// Style.screenshotEditor "swappy": the old way, swappy opens after saving.
// Ctrl+Print, recording picks and text picks never mark up.
//
// The same overlay picks what a screen recording takes (recordRegion():
// services/Recorder.qml gets the rectangle instead of a picture being cut),
// and where to read text from (text(): the piece goes through
// scripts/ocr.sh, the text is copied and a notification says how much).
//
// Its tools (`task`; the toolbar's second row of buttons, or a key in the
// overlay; IPC `screenshot text|qr|lens|translate` opens it on one):
//   text (T)       the words copied, as above
//   qr (Q)         QR codes and barcodes (scripts/qr-scan.sh, zbarimg;
//                  services/qr.js): a web link → a notification with Open
//                  and Copy; a Wi-Fi code → its name and password, Copy;
//                  anything else is copied and shown; several are all
//                  copied, but never a Wi-Fi password (only its name is
//                  said: pick that code alone) (scripts/qr-notify.sh)
//   lens (L)       Google Lens in the browser (scripts/lens.sh: the
//                  picture goes straight to Google, no file host)
//   translate (D)  the words read (scripts/ocr.sh, Vietnamese too when
//                  tesseract-data-vie is installed) and translated
//                  (services/Translator.qml); the overlay stays, with a card
//                  next to the pick: the text, its translation, Copy, the
//                  other way round; Esc or a click outside closes it
//
// MINE_SHOT_DRYRUN=1, MINE_SHOT_DIR and MINE_SHOT_FREEZE are for testing:
// nothing is copied, notified or opened, only printed (a marked-up picture
// is still saved, in MINE_SHOT_DIR; the QR notification's script runs,
// printing what it would do, MINE_SHOT_ANSWER being the button pressed).
Singleton {
    id: root

    property bool active: false        // the overlay is up
    property bool busy: false          // freezing or saving
    property string mode: "region"     // region | window | screen
    property bool edit: false
    property bool forRecording: false  // picking for Recorder, not a picture
    // What a pick is for: shot (a picture) | text | qr | lens | translate.
    property string task: "shot"
    readonly property bool forText: task === "text"     // picking text to copy (OCR)

    // The focused output: { name, x, y, width, height, scale } (logical, mango).
    property var monitor: null
    // Windows visible on it: [{ x, y, width, height, title, appid }], in the
    // output's own coordinates.
    property var windows: []
    property string frozen: ""         // the frozen screen, a file path

    // Marking up (Edit on): the overlay stays up on the pick.
    property bool marking: false
    // { x, y, w, h: the pick (logical, on the output); ox, oy, s: the frozen
    //   picture's corner (0, 0) and its pixels per logical px; px, py, pw,
    //   ph: what's cut out of it (its pixels, as captureRect cuts) }
    property var markGeo: null
    property var markPlain: []          // the plain cut's command, for Save with no marks
    property string markOut: ""         // where Save puts it
    property string editFile: ""        // a saved picture being marked up (its Save writes over it)
    readonly property bool markup: Style.screenshotEditor !== "swappy"

    readonly property bool dryRun: Quickshell.env("MINE_SHOT_DRYRUN") === "1"
    readonly property string dir: Quickshell.env("MINE_SHOT_DIR") || Style.screenshotDir
    readonly property string freezePath: Quickshell.env("MINE_SHOT_FREEZE")
        || (Quickshell.env("XDG_RUNTIME_DIR") + "/mine-shot-frozen.png")
    // The drawn marks on their way to shot-mark.sh (it removes them); a new
    // name each time, so a copy still being made never meets the next one.
    property string marksPath: ""
    function newMarksPath() {
        marksPath = Quickshell.env("XDG_RUNTIME_DIR") + "/mine-shot-marks-" + Date.now() + ".png";
    }

    // ---- Starting ------------------------------------------------------------------------
    function region() { forRecording = false; task = "shot"; start("region"); }
    function window() { forRecording = false; task = "shot"; start("window"); }
    function screen() { forRecording = false; task = "shot"; start("screen"); }
    // Pick what to record: the overlay comes up in region mode.
    function recordRegion() {
        if (active || busy)
            return;
        forRecording = true;
        task = "shot";
        start("region");
    }
    // Copy the text in a region (drag one, or click a window).
    function text() {
        useTool("text");
    }
    // Scan a QR code or barcode, search with Google Lens, translate.
    function qr() {
        useTool("qr");
    }
    function lens() {
        useTool("lens");
    }
    function translate() {
        useTool("translate");
    }
    // From a key or IPC: the overlay comes up on that tool, region mode; if
    // it's up already (picking a picture or another tool), the tool switches.
    function useTool(t) {
        if (busy || marking || translating || forRecording)
            return;
        if (active) {
            task = t;
            return;
        }
        task = t;
        start("region");
    }
    // The overlay's tool buttons and keys.
    function setTask(t) {
        if (active && !marking && !translating && !forRecording)
            task = t;
    }

    function start(m) {
        if (busy)
            return;
        if (active) {
            if (!marking && !translating)
                mode = m === "screen" ? mode : m;
            return;
        }
        mode = m;
        busy = true;
        monitors.running = true;        // → clients → grim
    }

    function close() {
        active = false;
        busy = false;
        forRecording = false;
        task = "shot";
        marking = false;
        markGeo = null;
        editFile = "";
        closeCard();
    }

    // ---- Capturing (from the overlay) -------------------------------------------------------
    // A rectangle in the output's logical coordinates.
    function captureRect(x, y, w, h) {
        if (!active || !monitor || w < 2 || h < 2)
            return;
        if (forRecording) {
            // wf-recorder wants global logical coordinates, inside the output.
            const rx = Math.max(0, x), ry = Math.max(0, y);
            const rw = Math.min(x + w, monitor.width) - rx, rh = Math.min(y + h, monitor.height) - ry;
            close();
            Recorder.recordRect(monitor.x + rx, monitor.y + ry, rw, rh);
            return;
        }
        const s = monitor.scale;
        const px = Math.max(0, Math.round(x * s));
        const py = Math.max(0, Math.round(y * s));
        const pw = Math.min(Math.round((x + w) * s), Math.round(monitor.width * s)) - px;
        const ph = Math.min(Math.round((y + h) * s), Math.round(monitor.height * s)) - py;
        if (task !== "shot") {
            const lx = Math.max(0, x), ly = Math.max(0, y);
            useOn(pw + "x" + ph + "+" + px + "+" + py,
                  { x: lx, y: ly, w: Math.min(x + w, monitor.width) - lx, h: Math.min(y + h, monitor.height) - ly });
            return;
        }
        const out = target();
        const plain = ["magick", "png:" + frozen, "-crop", pw + "x" + ph + "+" + px + "+" + py, "+repage", out];
        if (edit && markup) {
            beginMarkup({ x: x, y: y, w: w, h: h, ox: 0, oy: 0, s: s, px: px, py: py, pw: pw, ph: ph }, plain, out);
            return;
        }
        active = false;
        busy = true;
        save(plain, out);
    }

    // The whole frozen screen.
    function captureAll() {
        if (!active)
            return;
        if (forRecording) {
            const name = monitor?.name ?? "";
            close();
            Recorder.recordOutput(name);
            return;
        }
        if (task !== "shot") {
            useOn("", { x: 0, y: 0, w: monitor?.width ?? 0, h: monitor?.height ?? 0 });
            return;
        }
        const out = target();
        if (edit && markup && monitor) {
            const s = monitor.scale;
            beginMarkup({ x: 0, y: 0, w: monitor.width, h: monitor.height, ox: 0, oy: 0, s: s,
                          px: 0, py: 0, pw: Math.round(monitor.width * s), ph: Math.round(monitor.height * s) },
                        ["cp", frozen, out], out);
            return;
        }
        active = false;
        busy = true;
        save(["cp", frozen, out], out);
    }

    // Saving: the picture is made in the private runtime folder, then moved
    // to its name in the screenshots folder. A move replaces whatever is
    // there instead of writing through it, so a link someone left at that
    // name (Chrome's Flatpak can write to ~/Pictures) changes nothing else.
    // `cmd` writes `out`; it's given the private name instead.
    function save(cmd, out) {
        const tmp = Quickshell.env("XDG_RUNTIME_DIR") + "/mine-shot-save-" + Date.now() + ".png";
        crop.out = out;
        crop.command = ["sh", "-c", 'tmp=$1 out=$2; shift 2; "$@" && mkdir -p -- "$(dirname -- "$out")" && mv -f -- "$tmp" "$out" && exit 0; rm -f -- "$tmp"; exit 1',
                        "sh", tmp, out].concat(cmd.map(a => a === out ? tmp : a));
        crop.running = true;
    }

    // ---- Marking up ------------------------------------------------------------------------
    // The overlay stays; `plain` is what Save runs when nothing was drawn.
    function beginMarkup(geo, plain, out) {
        newMarksPath();
        markGeo = geo;
        markPlain = plain;
        markOut = out;
        marking = true;
    }

    // From the overlay: how ("save" | "copy"), the pick's geometry (for a
    // saved picture, its own size), the blurred rectangles and whether
    // marksPath holds drawn marks.
    function markupDone(how, geo, blurs, marked) {
        if (!active || !marking || busy)
            return;
        const picture = editFile !== "" ? editFile : frozen;
        const file = editFile;
        const cut = geo.pw + "x" + geo.ph + "+" + geo.px + "+" + geo.py;
        const any = marked || blurs.length > 0;
        const plain = markPlain;
        const out = file !== "" ? file : markOut;
        close();
        busy = true;
        // shot-mark.sh <picture> <cut> <marks.png|-> <out|-> <block> [blurs...]
        const bake = ["sh", Quickshell.shellDir + "/scripts/shot-mark.sh", picture, cut, marked ? marksPath : "-",
                      how === "copy" ? "-" : out, String(Math.max(2, Math.round(Style.screenshotPixelSize)))].concat(blurs);
        if (how === "copy") {
            // The clipboard only: nothing is kept.
            Sounds.screenshot();
            mark.forSave = false;
            mark.command = bake;
            mark.running = true;
            return;
        }
        if (!any) {
            if (file !== "") {
                // Nothing drawn on a saved picture: it stays as it is.
                finish(file);
                return;
            }
            // The plain cut, exactly as without Edit.
            save(plain, out);
            return;
        }
        mark.forSave = true;
        mark.out = out;
        mark.command = bake;
        mark.running = true;
    }

    // The notification's Edit (IPC `screenshot edit <file>`): "ok" when the
    // markup opens; anything else and shot-notify.sh opens swappy instead
    // (Style.screenshotEditor "swappy", busy, not a picture path).
    function editSaved(file) {
        if (!markup)
            return "swappy";
        if (active || busy)
            return "busy";
        if (!/^\/.*\.png$/i.test(file) || /[\n\r]/.test(file))
            return "not a png";
        newMarksPath();
        editFile = file;
        forRecording = false;
        task = "shot";
        busy = true;
        monitors.running = true;        // → the overlay, on the focused output
        return "ok";
    }

    // The saved picture couldn't be read.
    function editFailed() {
        console.warn("screenshot: can't read", editFile, "for editing");
        close();
    }

    // ~/Pictures/Screenshots/screenshot_2026-10-15_03-58-12.png
    function target() {
        return dir + "/screenshot_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".png";
    }

    function finish(file) {
        busy = false;
        Sounds.screenshot();
        // Edit with Style.screenshotEditor "swappy": swappy opens it (marking
        // up happened before saving otherwise).
        const swappy = edit && !markup;
        if (dryRun) {
            console.log("screenshot (dry run): saved", file, swappy ? "→ swappy" : "→ copy + notify");
            if (!swappy)
                Activities.screenshot(file);
            done(file);
            return;
        }
        // The live activity shows it; then the notification only goes to the
        // list (for its Open / Edit / Delete).
        const said = !swappy && Activities.screenshot(file);
        Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", file]);
        if (swappy)
            Quickshell.execDetached(["swappy", "-f", file]);
        else if (Style.screenshotNotify)
            Quickshell.execDetached(["sh", Quickshell.shellDir + "/scripts/shot-notify.sh", file, said ? "quiet" : ""]);
        done(file);
    }

    signal done(string file)

    // ---- Text (OCR) -------------------------------------------------------------------------
    // Style.ocrLanguages: "auto" (English, plus Vietnamese when installed) or
    // tesseract's own, e.g. "eng+vie".
    function readText(geometry) {
        active = false;
        busy = true;
        ocr.command = ["sh", Quickshell.shellDir + "/scripts/ocr.sh", frozen, geometry, Style.ocrLanguages || "auto"];
        ocr.running = true;
    }

    function gotText(raw) {
        busy = false;
        task = "shot";
        // Lines joined back up, empty lines kept as paragraph breaks.
        const text = raw.replace(/\f/g, "").replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
        const words = text === "" ? 0 : text.split(/\s+/).length;
        const first = text.split("\n")[0].trim();
        // As text: the body is markup, and a page can show "<a href=…>".
        const firstLine = (first.length > 90 ? first.substring(0, 89) + "…" : first)
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        // "--": the line read off the screen may start with "-" (any page can
        // show "--icon=..."); after it, it is only text.
        const note = words === 0
            ? ["notify-send", "-a", "Copy text", "-i", "edit-find", "Nothing found", "No text in that part of the screen"]
            : ["notify-send", "-a", "Copy text", "-i", "edit-copy", "--", "Copied " + words + (words === 1 ? " word" : " words"), firstLine];
        // The live activity says it, or (off, or a panel is open) the notification.
        const said = Activities.textRead(text, words);
        if (dryRun) {
            console.log("screenshot (dry run): text", JSON.stringify(text));
            if (words > 0)
                console.log("screenshot (dry run): wl-copy", words, "words");
            if (!said)
                console.log("screenshot (dry run):", JSON.stringify(note));
        } else {
            if (words > 0)
                Quickshell.execDetached(["wl-copy", "--", text]);
            if (!said)
                Quickshell.execDetached(note);
        }
        textRead(text);
    }

    signal textRead(string text)

    Process {
        id: ocr
        stdout: StdioCollector {
            onStreamFinished: root.gotText(text)
        }
        onExited: code => {
            if (code !== 0)
                console.warn("screenshot: reading text failed", code);
        }
    }

    // ---- The tools ---------------------------------------------------------------------------
    // A pick for a tool: `geometry` in the frozen picture's pixels ("" = all
    // of it), `geo` the pick on the output (logical, for the card).
    function useOn(geometry, geo) {
        switch (task) {
        case "text":
            readText(geometry);
            break;
        case "qr":
            scan(geometry);
            break;
        case "lens":
            searchLens(geometry);
            break;
        case "translate":
            readForTranslation(geometry, geo);
            break;
        }
    }

    // Copied by us: the clipboard's live activity needn't say it again.
    function copyText(text) {
        Activities.expectCopy();
        if (dryRun)
            console.log("screenshot (dry run): wl-copy", JSON.stringify(text));
        else
            Quickshell.execDetached(["wl-copy", "--", text]);
    }

    function say(icon, summary, body) {
        const note = ["notify-send", "-a", "Screenshot", "-i", icon, "--", summary, body];
        if (dryRun)
            console.log("screenshot (dry run):", JSON.stringify(note));
        else
            Quickshell.execDetached(note);
    }

    function shorten(text) {
        const t = String(text).trim();
        return t.length > 300 ? t.substring(0, 299) + "…" : t;
    }

    // ---- QR codes and barcodes -----------------------------------------------------------------
    function scan(geometry) {
        active = false;
        busy = true;
        scanner.command = ["sh", Quickshell.shellDir + "/scripts/qr-scan.sh", frozen, geometry];
        scanner.running = true;
    }

    // zbarimg's XML and exit code (0 found, 4 nothing) → the notification.
    function gotCodes(xml, code) {
        busy = false;
        task = "shot";
        const codes = Qr.parseZbarXml(xml);
        let note;
        if (codes.length === 0 && code !== 0 && code !== 4) {
            console.warn("screenshot: scanning failed", code);
            note = ["failed"];
        } else if (codes.length === 0) {
            note = ["none"];
        } else if (codes.length === 1) {
            const c = Qr.classify(codes[0]);
            const kind = Qr.typeName(c.type);
            if (c.kind === "url") {
                note = ["url", c.url, kind];
            } else if (c.kind === "wifi") {
                note = ["wifi", c.ssid, c.password, c.security, kind];
            } else {
                copyText(c.text);
                note = ["text", shorten(c.text), kind];
            }
        } else {
            // All copied in one go, except a Wi-Fi code: its password
            // only ever goes the careful way (picked alone).
            const kinds = codes.map(c => Qr.classify(c));
            const texts = codes.filter((c, i) => kinds[i].kind !== "wifi").map(c => c.data);
            const wifi = kinds.filter(k => k.kind === "wifi").map(k => "“" + k.ssid + "”");
            if (texts.length > 0)
                copyText(texts.join("\n"));
            const summary = texts.length === 0 ? codes.length + " Wi-Fi codes"
                : "Copied " + texts.length + (texts.length < codes.length ? " of " + codes.length : "") + " codes";
            const body = [texts.length > 0 ? shorten(texts.join("\n")) : "",
                          wifi.length > 0 ? "Wi-Fi " + wifi.join(", ") + ": pick it alone for its password" : ""]
                .filter(t => t !== "").join("\n");
            note = ["several", summary, body];
        }
        // scripts/qr-notify.sh waits for a button (notify-send -A): left
        // running on its own. In a dry run it only prints, so its output
        // is shown here.
        const command = ["sh", Quickshell.shellDir + "/scripts/qr-notify.sh"].concat(note);
        if (dryRun) {
            notifier.command = command;
            notifier.running = true;
        } else {
            Quickshell.execDetached(command);
        }
        scanned(codes);
    }

    signal scanned(var codes)

    Process {
        id: scanner
        property int code: -1
        property int pending: 0
        property string xml: ""
        onRunningChanged: if (running) {
            code = -1;
            pending = 2;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                scanner.xml = text;
                scanner.settle();
            }
        }
        onExited: exitCode => {
            code = exitCode;
            settle();
        }
        function settle() {
            if (pending > 0 && --pending === 0)
                root.gotCodes(xml, code);
        }
    }

    Process {
        id: notifier
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.log(text.trim())
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.log(text.trim())
        }
    }

    // ---- Google Lens ---------------------------------------------------------------------------
    // scripts/lens.sh: the browser posts the piece straight to Google.
    function searchLens(geometry) {
        active = false;
        busy = true;
        lensSearch.command = ["sh", Quickshell.shellDir + "/scripts/lens.sh", frozen, geometry];
        lensSearch.running = true;
    }

    signal lensOpened(string page)

    Process {
        id: lensSearch
        stdout: StdioCollector {
            id: lensOut
            onStreamFinished: if (root.dryRun && text.trim() !== "") console.log("screenshot (dry run): lens page", text.trim())
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.log(text.trim())
        }
        onExited: code => {
            root.busy = false;
            root.task = "shot";
            if (code !== 0) {
                console.warn("screenshot: Google Lens failed", code);
                root.say("dialog-error", "Google Lens didn't open", "Couldn't hand the picture to the browser");
                return;
            }
            root.lensOpened(lensOut.text.trim());
        }
    }

    // ---- Translating -----------------------------------------------------------------------------
    // The overlay stays (active) with the card next to the pick
    // (screenshot/TranslateCard.qml): reading → translating → done, or
    // empty (no text there) / failed (cardError says why).
    property bool translating: false
    property var cardGeo: null          // the pick: { x, y, w, h } (logical, on the output)
    property string cardState: ""       // reading | translating | done | empty | failed
    property string cardText: ""        // what was read, lines joined back up
    property string cardTranslation: ""
    property string cardFrom: ""        // the language it seems to be in ("" = Google tells)
    property string cardTo: ""
    property string cardError: ""
    property string cardNote: ""        // e.g. Vietnamese text needs tesseract-data-vie
    property string cardId: ""          // the request to services/Translator.qml
    property int picks: 0               // which pick a reading belongs to

    function readForTranslation(geometry, geo) {
        picks++;
        cardGeo = geo;
        cardState = "reading";
        cardText = "";
        cardTranslation = "";
        cardFrom = "";
        cardTo = "";
        cardError = "";
        cardNote = "";
        cardId = "";
        translating = true;
        readGeometry = geometry;
        // Style.ocrLanguages set: those. "auto": Vietnamese first when its
        // data is there (tesseract-data-vie), else English, and the card
        // says what's missing.
        const langs = Style.ocrLanguages || "auto";
        if (langs !== "auto") {
            readWith(langs);
            return;
        }
        // (One still running from a pick just closed answers for this one:
        // the languages are the same.)
        waitingLangs = true;
        if (!langCheck.running)
            langCheck.running = true;
    }
    property string readGeometry: ""
    property bool waitingLangs: false

    // The reading starts once the last one (a pick closed while it was
    // still reading) is over, so its text can't land on this pick.
    function readWith(langs) {
        transOcr.next = { pick: picks, command: ["sh", Quickshell.shellDir + "/scripts/ocr.sh", frozen, readGeometry, langs] };
        transOcr.go();
    }

    function gotTextToTranslate(raw) {
        const text = Lang.joinLines(raw);
        if (text === "") {
            cardState = "empty";
            return;
        }
        cardText = text;
        ask(Translator.targetFor(text), Translator.guess(text));
    }

    function ask(to, from) {
        if (cardId !== "")
            Translator.cancel(cardId);
        cardId = "screenshot-" + picks + "-" + Date.now();
        cardTo = to;
        cardFrom = from;
        cardTranslation = "";
        cardError = "";
        cardState = "translating";
        if (!Translator.request(cardId, cardText, to)) {
            cardState = "empty";
        }
    }

    // The card's ⇄: the other language of Style.translatePair, taking the
    // text to be in the one it went to (Vietnamese typed without accents
    // looks like English, for one).
    function swapDirection() {
        if (!translating || cardText === "" || cardState === "reading")
            return;
        const was = cardTo;
        ask(Translator.otherOf(was), was);
    }

    // The card's Try again (after it failed): the same once more.
    function retryTranslation() {
        if (translating && cardState === "failed" && cardText !== "")
            ask(cardTo, cardFrom);
    }

    // The card's Copy: the translation. true when there was one.
    function copyTranslation() {
        if (!translating || cardState !== "done" || cardTranslation === "")
            return false;
        copyText(cardTranslation);
        return true;
    }

    function closeCard() {
        if (cardId !== "")
            Translator.cancel(cardId);
        waitingLangs = false;
        transOcr.next = null;
        if (transOcr.running)
            transOcr.running = false;
        translating = false;
        cardGeo = null;
        cardState = "";
        cardId = "";
    }

    Connections {
        target: Translator
        function onFinished(id, ok, translation, from, to, error) {
            if (!root.translating || id !== root.cardId)
                return;
            root.cardId = "";
            root.cardTranslation = translation;
            root.cardError = error;
            root.cardState = ok ? "done" : "failed";
        }
    }

    Process {
        id: langCheck
        command: ["tesseract", "--list-langs"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.translating || !root.waitingLangs)
                    return;
                root.waitingLangs = false;
                const vie = /^vie$/m.test(text);
                root.cardNote = vie ? "" : "Vietnamese text needs tesseract-data-vie";
                root.readWith(vie ? "vie+eng" : "eng");
            }
        }
    }

    // One reading at a time: `next` starts when the one before has both
    // exited and finished its output (`pending`), so every output belongs
    // to the pick it was started for (`pick`).
    Process {
        id: transOcr
        property var next: null         // { pick, command }
        property int pick: 0
        property int pending: 0
        function go() {
            if (!next || pending > 0)
                return;
            pick = next.pick;
            command = next.command;
            next = null;
            pending = 2;
            running = true;
        }
        function settle() {
            if (pending > 0 && --pending === 0)
                Qt.callLater(go);
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.translating && transOcr.pick === root.picks)
                    root.gotTextToTranslate(text);
                transOcr.settle();
            }
        }
        onExited: code => {
            if (code !== 0 && root.translating && pick === root.picks)
                console.warn("screenshot: reading text to translate failed", code);
            settle();
        }
    }

    // ---- Steps ---------------------------------------------------------------------------
    // 1) which output has focus
    Process {
        id: monitors
        command: ["mmsg", "get", "all-monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text).monitors ?? [];
                    const m = list.find(o => o.active) ?? list[0];
                    root.monitor = m ? { name: m.name, x: m.x, y: m.y, width: m.width, height: m.height, scale: m.scale } : null;
                } catch (e) {
                    root.monitor = null;
                }
                if (!root.monitor) {
                    console.warn("screenshot: no monitor from mmsg");
                    root.busy = false;
                    root.editFile = "";
                    return;
                }
                if (root.editFile !== "") {
                    // A saved picture to mark up: no freezing, the overlay
                    // shows it on the dimmed screen.
                    root.busy = false;
                    root.marking = true;
                    root.active = true;
                    return;
                }
                if (root.mode === "screen") {
                    // No overlay: straight to the file.
                    const out = root.target();
                    root.save(["grim", "-o", root.monitor.name, out], out);
                } else {
                    clients.running = true;
                }
            }
        }
    }

    // 2) the windows you can see on it
    Process {
        id: clients
        command: ["mmsg", "get", "all-clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text).clients ?? [];
                } catch (e) {}
                const m = root.monitor;
                root.windows = list.filter(c => c.is_visible && c.monitor === m.name && !c.is_minimized)
                    .map(c => ({
                        x: c.x - m.x, y: c.y - m.y, width: c.width, height: c.height,
                        title: c.title ?? "", appid: c.appid ?? "",
                        floating: c.is_floating, fullscreen: c.is_fullscreen
                    }))
                    // Floating and fullscreen ones sit on top: they win the hover.
                    .sort((a, b) => (b.floating || b.fullscreen) - (a.floating || a.fullscreen));
                freeze.running = true;
            }
        }
    }

    // 3) freeze: the whole output, at full resolution
    Process {
        id: freeze
        command: ["grim", "-o", root.monitor?.name ?? "", root.freezePath]
        onExited: code => {
            if (code !== 0) {
                console.warn("screenshot: grim failed", code);
                root.busy = false;
                return;
            }
            root.frozen = root.freezePath;
            root.busy = false;
            root.active = true;         // the overlay comes up now
        }
    }

    // Marked up: scripts/shot-mark.sh blurs, lays the marks on and saves
    // (then finish()), or copies.
    Process {
        id: mark
        property bool forSave: false
        property string out: ""
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.log(text.trim())
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("screenshot:", text.trim())
        }
        onExited: code => {
            if (code !== 0) {
                // The overlay is gone already: say so, the marks are lost.
                console.warn("screenshot: marking up failed", code);
                root.busy = false;
                if (!root.dryRun)
                    Quickshell.execDetached(["notify-send", "-a", "Screenshot", "-i", "dialog-error",
                                             forSave ? "Screenshot not saved" : "Screenshot not copied",
                                             "Drawing the marks on it failed"]);
            } else if (forSave) {
                root.finish(out);
            } else {
                root.busy = false;
            }
        }
    }

    // 4) cut the picture out (or grim it straight for "screen")
    Process {
        id: crop
        property string out: ""
        onExited: code => {
            if (code === 0)
                root.finish(out);
            else {
                console.warn("screenshot: saving failed", code);
                root.busy = false;
            }
        }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", dir])
}
