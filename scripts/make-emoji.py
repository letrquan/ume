"""Writes services/emoji.json for the launcher's emoji mode (":").

The data comes from GTK 4's own emoji chooser (CLDR names, keywords and
groups, built into libgtk-4 as /org/gtk/libgtk/emoji/en.data), so it works
offline and matches what Noto Color Emoji draws.
Each entry: [emoji, name, "extra keywords", group]. U+1F3FB in GTK's data
marks "takes a skin tone"; it's dropped (the default yellow). Group 2 (hair
components) is left out: those aren't emoji on their own.
Run: python3 make-emoji.py <shell dir>/services/emoji.json"""
import json
import sys

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gio, GLib, Gtk  # noqa: F401  (Gtk registers the resource)

GROUPS = ["Smileys & emotion", "People & body", "Components", "Animals & nature",
          "Food & drink", "Travel & places", "Activities", "Objects", "Symbols", "Flags"]

data = Gio.resources_lookup_data("/org/gtk/libgtk/emoji/en.data", 0)
entries = GLib.Variant.new_from_bytes(GLib.VariantType.new("a(aussasasu)"), data, True).unpack()

out = []
for cps, name, _local, keywords, _kw2, group in entries:
    if group == 2:
        continue
    emoji = "".join(chr(c) for c in cps if c != 0x1F3FB)
    words = set(name.lower().replace(":", " ").split())
    extra = [k.lower() for k in keywords if k.lower() not in words]
    out.append([emoji, name, " ".join(dict.fromkeys(extra)), group])

with open(sys.argv[1], "w") as f:
    json.dump({"groups": GROUPS, "emoji": out}, f, ensure_ascii=False, separators=(",", ":"))
print(len(out), "emoji")
