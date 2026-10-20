.pragma library

// A tiny calculator for the launcher: numbers, + - * / % ^ and brackets.
// It reads the text itself (no eval), so typing can never run code.
// evaluate("2+3*4") === 14; anything else returns null.
function evaluate(text) {
    const s = text.replace(/\s+/g, "").replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, "/");
    // Only math characters, and at least one operator after the first sign.
    if (s === "" || !/^[0-9.+\-*/()%^]+$/.test(s) || !/[+\-*/%^]/.test(s.slice(1)))
        return null;
    let i = 0;

    function expr() {
        let v = term();
        while (s[i] === "+" || s[i] === "-") {
            const op = s[i++];
            const r = term();
            v = op === "+" ? v + r : v - r;
        }
        return v;
    }
    function term() {
        let v = power();
        while (s[i] === "*" || s[i] === "/" || s[i] === "%") {
            const op = s[i++];
            const r = power();
            v = op === "*" ? v * r : op === "/" ? v / r : v % r;
        }
        return v;
    }
    function power() {
        const base = unary();
        if (s[i] === "^") {
            i++;
            return Math.pow(base, power());
        }
        return base;
    }
    function unary() {
        if (s[i] === "-") {
            i++;
            return -unary();
        }
        if (s[i] === "+") {
            i++;
            return unary();
        }
        return atom();
    }
    function atom() {
        if (s[i] === "(") {
            i++;
            const v = expr();
            if (s[i++] !== ")")
                throw "bracket";
            return v;
        }
        const m = /^(\d+\.?\d*|\.\d+)/.exec(s.slice(i));
        if (!m)
            throw "number";
        i += m[0].length;
        return parseFloat(m[0]);
    }

    try {
        const v = expr();
        return i === s.length && isFinite(v) ? v : null;
    } catch (e) {
        return null;
    }
}

// 14, 0.333333333333, 1e+21 — no float noise like 0.30000000000000004.
function format(v) {
    return Number.isInteger(v) ? String(v) : String(parseFloat(v.toPrecision(12)));
}
