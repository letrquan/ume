.pragma library

// The text side of translating (services/Translator.qml): which language a
// piece of text looks like, which way to translate it, and OCR's line
// breaks joined back into sentences. No Qt in here, so a plain JS test can
// load it too.

// Letters only Vietnamese uses: đ ă ơ ư ĩ ũ and the vowels with a tone mark
// (Latin Extended Additional, U+1EA0–U+1EF9: ạ ả ấ ầ ẩ ẫ ậ … ỳ ỵ ỷ ỹ).
const VI_STRONG = /[đĐăĂơƠưƯĩĨũŨẠ-ỹ]/g;
// Accented letters Vietnamese shares with French, Spanish, Portuguese…
const VI_WEAK = /[àáâãèéêìíòóôõùúýÀÁÂÃÈÉÊÌÍÒÓÔÕÙÚÝ]/g;
// Letters Vietnamese never uses: with them it's some other language.
const NOT_VI = /[çñüöäëïßœæøåÇÑÜÖÄËÏŒÆØÅ]/;

// Languages told apart by their own script: [code, pattern]. Japanese
// first (it uses Chinese characters too, but kana only it has).
const SCRIPTS = [
    ["ja", /[぀-ヿ]/],
    ["ko", /[가-힯ᄀ-ᇿ]/],
    ["zh", /[一-鿿]/],
    ["ru", /[Ѐ-ӿ]/],
    ["th", /[฀-๿]/],
    ["ar", /[؀-ۿ]/],
    ["he", /[֐-׿]/],
    ["el", /[Ͱ-Ͽ]/],
    ["hi", /[ऀ-ॿ]/]
];

const NAMES = {
    en: "English", vi: "Vietnamese", ja: "Japanese", ko: "Korean", zh: "Chinese",
    "zh-CN": "Chinese", "zh-TW": "Chinese (Traditional)", ru: "Russian", th: "Thai",
    ar: "Arabic", he: "Hebrew", el: "Greek", hi: "Hindi", fr: "French", de: "German",
    es: "Spanish", it: "Italian", pt: "Portuguese", nl: "Dutch", id: "Indonesian",
    lo: "Lao", km: "Khmer", uk: "Ukrainian", pl: "Polish", tr: "Turkish"
};

// Latin letters, accented ones too (QML's JavaScript has no \p{L}).
const LATIN = /[A-Za-z\u00C0-\u024F\u1E00-\u1EFF]/g;

function count(text, re) {
    const m = text.match(re);
    return m ? m.length : 0;
}

// Vietnamese? One letter only Vietnamese has is enough (đ, ơ, ư, ạ, ả…);
// otherwise a good share of the accents it shares with other languages,
// and none it never uses. Plain ASCII Vietnamese (no accents) can't be
// told from English: the card's swap button is for that.
function looksVietnamese(text) {
    const t = String(text ?? "");
    const letters = count(t, LATIN);
    if (letters === 0)
        return false;
    if (count(t, VI_STRONG) >= 1)
        return true;
    const weak = count(t, VI_WEAK);
    return weak >= 2 && weak / letters >= 0.2 && !NOT_VI.test(t);
}

// The language the text looks like: "vi", one told by its script, or ""
// (anything else in Latin letters: English, French, … can't be told apart
// here; Google works it out).
function guess(text) {
    const t = String(text ?? "");
    for (const [code, re] of SCRIPTS) {
        if (re.test(t))
            return code;
    }
    return looksVietnamese(t) ? "vi" : "";
}

// "vi:en" → { mine: "vi", other: "en" }. Anything odd → the default.
function parsePair(pair) {
    const m = String(pair ?? "").trim().match(/^([A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?)\s*[:>,/ ]\s*([A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?)$/);
    if (!m || m[1].toLowerCase() === m[2].toLowerCase())
        return { mine: "vi", other: "en", ok: false };
    return { mine: m[1], other: m[2], ok: true };
}

// Which way: text in your language (the pair's first) goes to the other
// one, anything else to yours.
function targetFor(text, pair) {
    const p = parsePair(pair);
    return guess(text) === p.mine ? p.other : p.mine;
}

// The swap button: the pair's other language.
function otherOf(code, pair) {
    const p = parsePair(pair);
    return code === p.mine ? p.other : p.mine;
}

function languageName(code) {
    if (!code)
        return "";
    return NAMES[code] ?? NAMES[code.split("-")[0]] ?? code.toUpperCase();
}

function isLower(ch) {
    return ch.toLowerCase() === ch && ch.toUpperCase() !== ch;
}

// OCR breaks lines where the screen did; a sentence split over two lines
// translates badly. Lines are joined back up (a word cut with a hyphen
// too), paragraphs (an empty line) and list items stay apart.
function joinLines(text) {
    const paragraphs = String(text ?? "").replace(/\r/g, "").replace(/\f/g, "")
        .split(/\n[ \t]*\n+/).map(p => p.trim()).filter(p => p !== "");
    return paragraphs.map(p => {
        const lines = p.split("\n").map(l => l.trim()).filter(l => l !== "");
        let out = "";
        for (const line of lines) {
            if (out === "")
                out = line;
            else if (/^([-•*·▪◦‣–]|\d+[.)])\s/.test(line))
                out += "\n" + line;
            else if (/[A-Za-z\u00C0-\u024F\u1E00-\u1EFF]-$/.test(out) && isLower(line[0]))
                out = out.slice(0, -1) + line;
            else
                out += " " + line;
        }
        return out;
    }).join("\n\n");
}
