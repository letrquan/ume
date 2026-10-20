.pragma library

// The on-screen keyboard's two pages, four rows each. Every row adds up to
// 11.5 units wide, so the keys line up from row to row.
//
// A key is { id, c, s, w, t }:
//   c  the character it types; s  the one it types with ⇧ (letters: the
//      capital), shown small in the corner when it isn't just the capital
//   t  instead of a character: shift, back, enter, tab, esc, page (?123 /
//      ABC), ctrl, alt, super, left, right, up, down, hide
//   w  width in units (1 = a letter key)
//   id what tests call it (c, or t; the space bar is "space")
// The bottom row is the same on both pages.

function ch(c, s) {
    return { id: c, c: c, s: s ?? c.toUpperCase(), w: 1 };
}

function special(t, w) {
    return { id: t, t: t, w: w ?? 1 };
}

function letters(text) {
    return text.split("").map(c => ch(c));
}

const bottom = [
    special("page", 1.25), special("ctrl"), special("alt"), special("super"),
    { id: "space", c: " ", s: " ", w: 3.25 },
    special("left", 0.75), special("up", 0.75), special("down", 0.75), special("right", 0.75),
    special("hide")
];

// QWERTY. ⇧ , . - give ! ? _ (like a phone), the rest of the symbols are on
// the ?123 page.
const letterRows = [
    letters("qwertyuiop").concat([special("back", 1.5)]),
    [special("tab")].concat(letters("asdfghjkl"), [special("enter", 1.5)]),
    [special("shift", 1.5)].concat(letters("zxcvbnm"), [ch(",", "!"), ch(".", "?"), ch("-", "_")]),
    bottom
];

// Digits and symbols; ⇧ gives the rarer ones (on the digits, what ⇧ gives
// on a real keyboard). Every ASCII symbol is on this page, with or without ⇧.
const symbolRows = [
    [ch("1", "!"), ch("2", "@"), ch("3", "#"), ch("4", "$"), ch("5", "%"), ch("6", "^"), ch("7", "&"),
     ch("8", "*"), ch("9", "("), ch("0", ")"), special("back", 1.5)],
    [special("esc"), ch("-", "_"), ch("/", "\\"), ch(":", "|"), ch(";", "~"), ch("(", "["), ch(")", "]"),
     ch("$", "{"), ch("&", "}"), ch("@", "`"), special("enter", 1.5)],
    [special("shift", 1.5), ch("'"), ch("\""), ch(".", ">"), ch(",", "<"), ch("?"), ch("!"), ch("#"),
     ch("="), ch("*"), ch("+")],
    bottom
];

function rows(page) {
    return page === "symbols" ? symbolRows : letterRows;
}

// Units per row (all rows are the same).
const units = 11.5;
