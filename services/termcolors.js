.pragma library

// The terminal's 16 colors for the wallpaper's scheme (foot, and starship's
// prompt). Material's roles are all shades of the wallpaper's own color, so
// using them as ANSI colors made green, yellow, magenta and cyan come out
// the same; matugen's own "custom colors" give no usable bright set. So the
// six usual hues are made here: each turned a little toward the wallpaper's
// color (at most 10°, none for a grey picture), at a lightness that reads on
// the terminal's background; the bright ones a step lighter. Black, white
// and their bright pair are the scheme's own greys.
//
// palette(pick, dark) -> { term_red: "#rrggbb", term_bright_red: …, … }
// pick(role) gives a scheme role's "#rrggbb" (Wallpaper.qml's pick).
// Done in OKLCH, where the same lightness looks the same for every hue.

// Hue (OKLCH degrees), and lightness + chroma on a dark and a light
// background. Yellow needs more light than the others to still look yellow.
const HUES = {
    red:     { h: 25,  dark: [0.72, 0.15], light: [0.55, 0.17] },
    green:   { h: 145, dark: [0.78, 0.15], light: [0.56, 0.15] },
    yellow:  { h: 92,  dark: [0.86, 0.13], light: [0.58, 0.13] },
    blue:    { h: 255, dark: [0.74, 0.13], light: [0.52, 0.16] },
    magenta: { h: 330, dark: [0.74, 0.15], light: [0.53, 0.17] },
    cyan:    { h: 200, dark: [0.80, 0.11], light: [0.57, 0.11] }
};
const BRIGHT_STEP = 0.07;       // lighter
const BRIGHT_CHROMA = 0.9;      // and a little softer
const PULL = 0.2;               // share of the way toward the wallpaper's hue
const PULL_MAX = 10;            // degrees

function palette(pick, dark) {
    const source = toOklch(pick("source_color"));
    // A grey picture has no hue to turn toward.
    const grip = Math.min(1, source.c / 0.05);
    const out = {};
    for (const name in HUES) {
        const hue = HUES[name];
        const [l, c] = dark ? hue.dark : hue.light;
        let delta = ((source.h - hue.h + 540) % 360) - 180;
        const h = hue.h + Math.sign(delta) * Math.min(Math.abs(delta) * PULL, PULL_MAX) * grip;
        out["term_" + name] = toHex(l, c, h);
        out["term_bright_" + name] = toHex(l + BRIGHT_STEP, c * BRIGHT_CHROMA, h);
    }
    // Black and white: visible on the background (dark) or as text (light);
    // bright black is the dim grey for comments and fish's suggestions.
    out.term_black = pick(dark ? "surface_container_highest" : "on_surface_variant");
    out.term_bright_black = pick("outline");
    out.term_white = pick(dark ? "on_surface_variant" : "outline_variant");
    out.term_bright_white = pick(dark ? "on_surface" : "surface_container_highest");
    return out;
}

// ---- OKLCH ↔ sRGB ----------------------------------------------------------------

function toLinear(v) {
    return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}
function fromLinear(v) {
    return v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
}

function toOklch(hex) {
    const n = parseInt(String(hex).replace("#", ""), 16) || 0;
    const r = toLinear((n >> 16 & 255) / 255), g = toLinear((n >> 8 & 255) / 255), b = toLinear((n & 255) / 255);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    const A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    const B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    return { l: L, c: Math.hypot(A, B), h: (Math.atan2(B, A) * 180 / Math.PI + 360) % 360 };
}

// Linear sRGB for an OKLCH color (may be out of range).
function toRgb(L, C, h) {
    const A = C * Math.cos(h * Math.PI / 180), B = C * Math.sin(h * Math.PI / 180);
    const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
    const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
    const s = Math.pow(L - 0.0894841775 * A - 1.2914855480 * B, 3);
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s];
}

// Out of what a screen can show: less chroma (same lightness and hue) until it fits.
function toHex(L, C, h) {
    L = Math.max(0, Math.min(1, L));
    const fits = c => toRgb(L, c, h).every(v => v >= -0.0001 && v <= 1.0001);
    if (!fits(C)) {
        let lo = 0, hi = C;
        for (let i = 0; i < 20; i++) {
            const mid = (lo + hi) / 2;
            if (fits(mid))
                lo = mid;
            else
                hi = mid;
        }
        C = lo;
    }
    return "#" + toRgb(L, C, h).map(v => {
        const byte = Math.round(Math.max(0, Math.min(1, fromLinear(Math.max(0, v)))) * 255);
        return byte.toString(16).padStart(2, "0");
    }).join("");
}
