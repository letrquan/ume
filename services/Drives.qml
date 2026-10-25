pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// USB drives (and SD cards): what's plugged in, for the bar's "drives" item
// and its popup (control/DrivesPopup.qml), and a notification when one
// comes in, with Open and Eject.
//  - Noticing: `udisksctl monitor` runs with the shell (it also starts
//    udisks, which is only started on demand here). Its lines are only a
//    sign that something changed: 1 s after they stop, the list is read
//    again with `lsblk -J` (what's there, sizes, labels, where it's mounted,
//    used and free), and once more 2 s after a new drive, since its
//    partitions and their labels come a moment after the disk itself.
//  - Which: a whole disk on USB, or an SD card / other disk that says it's
//    removable. Never the internal disks (the NVMe and its Windows NTFS
//    partitions: not removable), zram, loop or RAM disks, nor any disk with
//    a partition mounted as /, /boot, /home, /usr, /var … or used as swap.
//    Partitions shown: the ones with a file system, except swap, encrypted
//    (LUKS), LVM / RAID members and Windows' own reserved / recovery / EFI
//    partitions. (An NTFS USB disk is shown: only its type says "Windows".)
//  - Open: mounts the biggest partition if it isn't (`udisksctl mount -b`,
//    a password dialog only if udisks asks for one), reads the list again
//    for where it went, and opens that folder (`xdg-open`).
//  - Eject: unmounts each mounted partition, the hidden ones too
//    (`udisksctl unmount -b`), stops at the first that is still in use and
//    says so, then powers the drive off (`udisksctl power-off -b`): "Safe to
//    remove". If it can't be powered off, a fresh listing decides: nothing
//    of it mounted = unmounted and safe (and why it isn't off), else
//    "Don't unplug yet" and what is still in use.
// Drives there when the shell starts aren't announced, only new ones.
//
// Tests: MINE_DRIVES_DRYRUN=1 (mount / unmount / power-off / xdg-open /
// notify-send are logged, not run; they count as done),
// MINE_DRIVES_MONITOR_CMD and MINE_DRIVES_LIST_CMD (sh -c text run instead
// of `udisksctl monitor` and the lsblk listing).
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_DRIVES_DRYRUN") === "1"
    readonly property string monitorCmd: Quickshell.env("MINE_DRIVES_MONITOR_CMD") ?? ""
    readonly property string listCmd: Quickshell.env("MINE_DRIVES_LIST_CMD") ?? ""

    readonly property bool enabled: Style.drivesWatch

    // ---- What's plugged in ---------------------------------------------------------------
    // From the last listing: [{ key, name ("sdb"), dev ("/dev/sdb"), card (an
    // SD card), title, model, size, sizeText, parts: [{ dev, label, fstype,
    // size, mount, used, avail }] (the ones shown), mounted, used, avail,
    // inUse: [{ dev, mount, label }] (everything of it mounted, shown or not) }].
    property var raw: []
    property var busyOf: ({})           // key → "opening" | "ejecting"
    property var noteOf: ({})           // key → the last thing said about it
    readonly property var drives: raw.map(d => Object.assign({}, d, { busy: busyOf[d.key] ?? "", note: noteOf[d.key] ?? "" }))
    readonly property int count: raw.length
    property bool listed: false         // the first listing is in

    function find(key) {
        return raw.find(d => d.key === key || d.name === key || d.dev === key) ?? null;
    }

    // ---- Watching (udisksctl monitor) ------------------------------------------------------
    Process {
        id: monitor
        command: root.monitorCmd !== "" ? ["sh", "-c", root.monitorCmd] : root.wrap(["udisksctl", "monitor"])
        stdout: SplitParser {
            onRead: line => root.heard(line)
        }
        onExited: code => {
            if (!root.enabled)
                return;
            // Not installed: nothing to wait for. Otherwise (udisks
            // restarted…) start again, waiting longer each time.
            if (code === 127) {
                console.log("drives: udisksctl isn't installed; only the first listing");
                return;
            }
            retry.interval = Math.min(60000, retry.interval * 2);
            retry.restart();
        }
    }
    Timer {
        id: retry
        interval: 2500
        onTriggered: if (root.enabled) monitor.running = true
    }

    function start() {
        if (enabled) {
            retry.interval = 2500;
            monitor.running = true;
            relist();
        } else {
            monitor.running = false;
            retry.stop();
            raw = [];
            listed = false;
        }
    }
    onEnabledChanged: start()
    Component.onCompleted: start()

    // "16:41:51.519: Added /org/freedesktop/UDisks2/block_devices/sdb" and
    // "…/block_devices/sdb1: org.freedesktop.UDisks2.Filesystem: Properties
    // Changed" (mounted or not); the indented lines under them are details.
    function heard(line) {
        if (!/^\d\d:\d\d:\d\d\.\d+: /.test(line))
            return;
        if (/\/block_devices\/|\/drives\/|udisks-daemon is running/.test(line))
            quiet.restart();
    }
    Timer {
        id: quiet
        interval: 1000
        onTriggered: root.relist()
    }

    // ---- Listing (lsblk) -------------------------------------------------------------------
    property bool listAgain: false
    property var waiting: []            // functions to call after the next listing

    function relist() {
        if (lister.running) {
            listAgain = true;
            return;
        }
        lister.exec(listCmd !== "" ? ["sh", "-c", listCmd]
            : wrap(["lsblk", "-J", "-b", "-o", "NAME,PATH,TYPE,SIZE,RM,HOTPLUG,TRAN,FSTYPE,LABEL,MOUNTPOINTS,FSUSED,FSAVAIL,MODEL,VENDOR,PARTTYPE"]));
    }
    function relistThen(fn) {
        waiting = waiting.concat([fn]);
        relist();
    }

    Job {
        id: lister
        onResult: (code, out, err) => {
            if (root.listAgain) {
                root.listAgain = false;
                root.relist();
                return;
            }
            const list = code === 0 ? root.parse(out) : null;
            if (list === null)
                console.log("drives: listing failed (" + code + "):", err.trim());
            else
                root.take(list);
            const fns = root.waiting;
            root.waiting = [];
            for (const fn of fns)
                fn();
        }
    }

    function yes(v) {
        return v === true || v === 1 || v === "1";
    }
    function num(v) {
        const n = Number(v);
        return isFinite(n) && n > 0 ? n : 0;
    }
    function mountsOf(b) {
        return (b.mountpoints ?? (b.mountpoint !== undefined ? [b.mountpoint] : [])).filter(m => typeof m === "string" && m !== "");
    }
    // Mounted where the system lives: never a "USB drive" to eject. (Only
    // these exact places: a stick mounted at ~/usb is still a stick.)
    function systemMount(m) {
        return m === "/" || m === "[SWAP]" || /^\/(boot|boot\/efi|efi|home|usr|var|var\/home|opt|srv|root|nix|gnu)$/.test(m);
    }
    // USB; an SD card; or anything else (but an NVMe) that says it's removable.
    function removable(d) {
        if (d.type !== "disk" || /^(zram|loop|ram|md|dm-|sr|nbd)/.test(d.name ?? ""))
            return false;
        const tran = d.tran ?? "";
        return tran === "usb"
            || ((tran === "mmc" || tran === "sdio") && (yes(d.rm) || yes(d.hotplug)))
            || (yes(d.rm) && tran !== "nvme");
    }
    // Windows' own partitions (GPT types): reserved, recovery, EFI system.
    readonly property var hiddenTypes: ["e3c9e316-0b5c-4db8-817d-f92df00215ae", "de94bba4-06d1-4d40-a16a-bfd50179d6ac",
                                        "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"]
    readonly property var unusable: ["swap", "crypto_LUKS", "LVM2_member", "linux_raid_member", "zfs_member", "BitLocker"]
    function usable(b) {
        return (b.fstype ?? "") !== "" && !unusable.includes(b.fstype)
            && !hiddenTypes.includes(String(b.parttype ?? "").toLowerCase());
    }

    function sizeText(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let v = bytes, i = 0;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1).replace(/\.0$/, "")) + " " + units[i];
    }

    // lsblk -J: { blockdevices: [{ name, path, type, size, rm, hotplug, tran,
    // fstype, label, mountpoints, fsused, fsavail, model, vendor, parttype,
    // children: [...] }] } (rm / hotplug are true/false, or "0"/"1" in older
    // versions). null = not lsblk's JSON.
    function parse(text) {
        let tree;
        try {
            tree = JSON.parse(text).blockdevices;
        } catch (e) {
            return null;
        }
        if (!Array.isArray(tree))
            return null;
        const out = [];
        for (const d of tree) {
            if (!removable(d))
                continue;
            const kids = (d.children ?? []).filter(c => c.type === "part");
            const all = [d].concat(d.children ?? []);
            if (all.some(b => mountsOf(b).some(systemMount)))
                continue;
            // A stick with no partition table: the file system is on the disk itself.
            const parts = (kids.length > 0 ? kids : [d]).filter(usable).map(b => ({
                dev: b.path || "/dev/" + b.name,
                label: b.label ?? "",
                fstype: b.fstype ?? "",
                size: num(b.size),
                mount: mountsOf(b)[0] ?? "",
                used: num(b.fsused),
                avail: num(b.fsavail)
            }));
            const model = [d.vendor, d.model].map(s => String(s ?? "").trim()).filter(s => s !== "").join(" ");
            const size = num(d.size);
            const mounted = parts.filter(p => p.mount !== "");
            // Everything of it in use, shown or not (an EFI partition a file
            // manager mounted, swap…): Eject must unmount it all, and it's
            // only safe to unplug once nothing is left.
            const inUse = [];
            for (const b of all)
                for (const m of mountsOf(b))
                    inUse.push({ dev: b.path || "/dev/" + b.name, mount: m, label: b.label ?? "" });
            const tran = d.tran ?? "";
            out.push({
                key: d.name + ":" + size + ":" + model,
                name: d.name,
                card: tran === "mmc" || tran === "sdio",      // an SD card (icon, wording)
                dev: d.path || "/dev/" + d.name,
                title: parts.find(p => p.label !== "")?.label || model || "USB drive",
                model: model,
                size: size,
                sizeText: sizeText(size),
                parts: parts,
                mounted: mounted.length > 0,
                inUse: inUse,
                used: mounted.reduce((s, p) => s + p.used, 0),
                avail: mounted.reduce((s, p) => s + p.avail, 0)
            });
        }
        return out;
    }

    // ---- New ones: a notification ---------------------------------------------------------
    property var fresh: []              // keys waiting to be announced
    property bool announceNext: false

    function take(list) {
        const before = raw.map(d => d.key);
        const keys = list.map(d => d.key);
        raw = list;
        // Gone: forget what was going on with them.
        const keep = o => {
            const left = {};
            for (const k in o)
                if (keys.includes(k))
                    left[k] = o[k];
            return left;
        };
        busyOf = keep(busyOf);
        noteOf = keep(noteOf);
        if (!listed) {
            listed = true;          // there already: not "plugged in"
            return;
        }
        const added = keys.filter(k => !before.includes(k));
        if (added.length > 0) {
            console.log("drives: plugged in:", added.join(", "));
            fresh = fresh.concat(added);
            settle.restart();
        }
        const gone = before.filter(k => !keys.includes(k));
        if (gone.length > 0)
            console.log("drives: gone:", gone.join(", "));
        if (announceNext) {
            announceNext = false;
            const now = fresh.filter(k => keys.includes(k));
            fresh = [];
            for (const k of now)
                announce(find(k));
        }
    }
    // Its partitions and labels a moment later, then the notification.
    Timer {
        id: settle
        interval: 2000
        onTriggered: {
            root.announceNext = true;
            root.relist();
        }
    }

    // A notification's body is markup; a drive's label and model are the
    // stick's own words (a label can be `<a href=…>Open files</a>`): text.
    function markupSafe(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function announce(d) {
        if (!d || !Style.drivesNotify)
            return;
        const body = markupSafe(d.title + " · " + d.sizeText + (d.model !== "" && d.model !== d.title ? " · " + d.model : ""));
        const cmd = ["notify-send", "-a", "Drives", "-i", "drive-removable-media", "-h", "string:category:device.added",
                     "-A", "open=Open", "-A", "eject=Eject", "--", d.card ? "SD card inserted" : "USB drive plugged in", body];
        if (dryRun) {
            console.log("drives (dry run):", JSON.stringify(cmd));
            return;
        }
        notice.createObject(root, { key: d.key }).exec(cmd);
    }

    // notify-send waits while the notification is around and prints the
    // button pressed; one of these per notification.
    Component {
        id: notice

        Process {
            property string key
            stdout: SplitParser {
                onRead: line => {
                    if (line === "open")
                        root.open(key);
                    else if (line === "eject")
                        root.eject(key);
                }
            }
            onExited: destroy()
        }
    }

    // ---- Open ----------------------------------------------------------------------------
    function setBusy(key, what) {
        const b = Object.assign({}, busyOf);
        if (what === "")
            delete b[key];
        else
            b[key] = what;
        busyOf = b;
    }
    function note(key, text) {
        const n = Object.assign({}, noteOf);
        n[key] = text;
        noteOf = n;
    }

    function open(key) {
        const d = find(key);
        if (!d || busyOf[d.key])
            return;
        // The biggest partition (a mounted one first).
        const parts = d.parts.slice().sort((a, b) => (b.mount !== "") - (a.mount !== "") || b.size - a.size);
        const p = parts[0];
        if (!p) {
            note(d.key, "Nothing on it to open");
            tell("Nothing to open", d.title + " has no file system this computer can read.");
            return;
        }
        if (p.mount !== "") {
            note(d.key, "");
            reveal(p.mount);
            return;
        }
        setBusy(d.key, "opening");
        note(d.key, "");
        run(["udisksctl", "mount", "-b", p.dev], (code, out, err) => {
            if (code !== 0) {
                setBusy(d.key, "");
                const why = reason(err || out, code);
                note(d.key, why);
                tell("Couldn't open " + d.title, why);
                return;
            }
            // "Mounted /dev/sdb1 at /run/media/user/USB" (older: with a ".").
            const said = (out.match(/^Mounted \S+ at (.+?)\.?\s*$/m) ?? [])[1] ?? "";
            relistThen(() => {
                setBusy(d.key, "");
                const where = find(d.key)?.parts.find(x => x.dev === p.dev)?.mount || said;
                if (where !== "")
                    reveal(where);
                else if (!dryRun)
                    note(d.key, "Mounted, but where isn't known");
            });
        });
    }

    function reveal(path) {
        const cmd = ["xdg-open", path];
        if (dryRun)
            console.log("drives (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // ---- Eject -----------------------------------------------------------------------------
    function eject(key) {
        const d = find(key);
        if (!d || busyOf[d.key])
            return;
        setBusy(d.key, "ejecting");
        note(d.key, "");
        // Every mounted partition, the hidden ones too (swap can't be unmounted
        // here: power-off refuses, and the message says why).
        const mounted = d.inUse.filter(p => p.mount !== "[SWAP]");
        const step = i => {
            if (i < mounted.length) {
                const p = mounted[i];
                run(["udisksctl", "unmount", "-b", p.dev], (code, out, err) => {
                    if (code === 0) {
                        step(i + 1);
                        return;
                    }
                    setBusy(d.key, "");
                    const text = err || out;
                    const inUse = /DeviceBusy|target is busy|is busy/i.test(text);
                    const name = p.label || p.dev;
                    const why = inUse ? name + " is still in use: close the files and windows open on it, then eject again."
                                      : reason(text, code);
                    note(d.key, inUse ? "In use: close what's open on it" : why);
                    tell("Can't eject " + d.title, why);
                    relist();
                });
                return;
            }
            run(["udisksctl", "power-off", "-b", d.dev], (code, out, err) => {
                if (code === 0) {
                    setBusy(d.key, "");
                    note(d.key, "Safe to remove");
                    tell("Safe to remove", d.title + " can be unplugged now.");
                    relist();
                    return;
                }
                // Not off: safe only if a fresh look finds nothing of it in use.
                const why = reason(err || out, code);
                relistThen(() => {
                    setBusy(d.key, "");
                    const left = find(d.key)?.inUse ?? [];
                    if (left.length === 0) {
                        note(d.key, "Unmounted: safe to remove");
                        tell(d.title + " is unmounted", "Safe to remove, but it couldn't be powered off: " + why);
                    } else {
                        const what = left[0].mount === "[SWAP]" ? left[0].dev + " is used as swap" : left[0].dev + " is still mounted";
                        note(d.key, "Not safe to remove yet");
                        tell("Don't unplug " + d.title + " yet", what + " (" + why + ").");
                    }
                });
            });
        };
        step(0);
    }

    // udisks' errors: "Error unmounting /dev/sdb1: GDBus.Error:org.freedesktop.
    // UDisks2.Error.DeviceBusy: Error unmounting /dev/sdb1: target is busy"
    // → "target is busy".
    function reason(text, code) {
        const lines = String(text).split("\n").map(l => l.trim()).filter(l => l !== "");
        const last = lines.length > 0 ? lines[lines.length - 1] : "";
        if (/NotAuthorized/.test(last))
            return "Not allowed";
        const bits = last.split(": ").filter(b => b !== "");
        return bits.length > 0 ? bits[bits.length - 1] : "failed (" + code + ")";
    }

    function tell(summary, body) {
        const cmd = ["notify-send", "-a", "Drives", "-i", "drive-removable-media", "--", summary, markupSafe(body)];
        if (dryRun)
            console.log("drives (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // ---- Running a command -----------------------------------------------------------------
    // done(code, out, err) once it has exited and both outputs were read.
    // The dry run only logs it, and it counts as done.
    function run(cmd, done) {
        if (dryRun) {
            console.log("drives (dry run):", JSON.stringify(cmd));
            Qt.callLater(() => done(0, "", ""));
            return;
        }
        console.log("drives:", cmd.join(" "));
        const job = jobs.createObject(root);
        job.result.connect((code, out, err) => {
            job.destroy();
            done(code, out, err);
        });
        job.exec(wrap(cmd));
    }
    Component {
        id: jobs
        Job {}
    }

    // Through sh: a missing program is exit 127 with a message, not a failed start.
    function wrap(cmd) {
        return ["sh", "-c", "command -v \"$1\" >/dev/null || { echo \"$1: not installed\" >&2; exit 127; }; exec \"$@\"", "sh"].concat(cmd);
    }

    // For IPC and tests.
    function status() {
        return JSON.stringify(drives.map(d => ({
            key: d.key, title: d.title, size: d.sizeText, busy: d.busy, note: d.note,
            parts: d.parts.map(p => p.dev + (p.mount !== "" ? "@" + p.mount : ""))
        })));
    }

    // A command whose answer counts once it has exited AND both its outputs
    // were read (they can come in either order).
    component Job: Process {
        id: job
        property int code: -1
        property int parts: 0
        signal result(int code, string out, string err)
        function part() {
            if (++parts === 3)
                result(code, outText.text, errText.text);
        }
        onRunningChanged: if (running) parts = 0
        stdout: StdioCollector {
            id: outText
            onStreamFinished: job.part()
        }
        stderr: StdioCollector {
            id: errText
            onStreamFinished: job.part()
        }
        onExited: c => {
            code = c;
            part();
        }
    }
}
