.pragma library

// A notification's body may carry a little markup (the notification spec:
// <b> <i> <u> <a href> <img>). It's shown with Text.StyledText, which would
// take much more, <img src="http://…"> too: a picture fetched from the
// internet the moment it shows (whoever sent it learns you read it, from
// your own address, past the browser's proxy). Taking tags out one by one
// can be fooled (<im<img>g …> leaves an <img>), so: tags other than <b> <i>
// <u> <br> and links to http(s) pages are taken out once, then everything
// is made text, then only those few are let back in. Whatever a trick
// leaves behind is shown as text, never read as a tag. Running it again on
// its own result changes nothing (saved notifications are cleaned again).
function body(text) {
    let s = String(text ?? "");
    s = s.replace(/<\/?([a-z][a-z0-9]*)\b[^<>]*>/gi, (m, tag) => {
        const t = tag.toLowerCase();
        if (t === "b" || t === "i" || t === "u" || t === "br")
            return m;
        if (t === "a")
            return /^<\/a\s*>$/i.test(m) || /^<a\s+href=("|')https?:\/\//i.test(m) ? m : "";
        return "";
    });
    // A lone & (not an entity like &amp;) is text.
    s = s.replace(/&(?!(?:[a-z][a-z0-9]*|#[0-9]+|#x[0-9a-f]+);)/gi, "&amp;");
    s = s.replace(/</g, "&lt;").replace(/>/g, "&gt;");
    s = s.replace(/&lt;(\/?)(b|i|u)&gt;/gi, (m, slash, tag) => "<" + slash + tag.toLowerCase() + ">");
    s = s.replace(/&lt;br\s*\/?&gt;/gi, "<br>");
    s = s.replace(/&lt;a\s+href=("|')(https?:\/\/(?:[^"'\s&]|&amp;)+)\1\s*&gt;/gi, (m, q, url) => '<a href="' + url + '">');
    s = s.replace(/&lt;\/a\s*&gt;/gi, "</a>");
    return s;
}
