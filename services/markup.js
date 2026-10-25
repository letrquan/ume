.pragma library

// A notification's body may carry a little markup (the notification spec:
// <b> <i> <u> <a href> <img>). It's shown with Text.StyledText, which would
// take much more, <img src="http://…"> too: a picture fetched from the
// internet the moment it shows (whoever sent it learns you read it, from
// your own address, past the browser's proxy). Taking tags out one by one
// can be fooled (<im<img>g …> leaves an <img>), so: the few tags let
// through (<b> <i> <u> <br>, links to http(s) pages) are set aside first,
// each replaced by a mark, any other tag is taken out, then everything left
// is made text, and only then are the set-aside tags put back. So text that
// is already escaped stays text: an app (or KDE Connect, for a text message
// from anyone) that sends "&lt;a href='https://…'&gt;" means those
// characters, never a link. Whatever a trick leaves behind is shown as
// text, never read as a tag. Running it again on its own result changes
// nothing (saved notifications are cleaned again).
function body(text) {
    // The marks are two private-use characters; any in the text itself go.
    let s = String(text ?? "").replace(/[\uE000\uE001]/g, "");
    const kept = [];
    const keep = tag => "\uE000" + (kept.push(tag) - 1) + "\uE001";
    s = s.replace(/<\/?([a-z][a-z0-9]*)\b[^<>]*>/gi, m => {
        const simple = m.match(/^<(\/?)(b|i|u)\s*>$/i);
        if (simple)
            return keep("<" + simple[1] + simple[2].toLowerCase() + ">");
        if (/^<br\s*\/?>$/i.test(m))
            return keep("<br>");
        if (/^<\/a\s*>$/i.test(m))
            return keep("</a>");
        // A link's address: http(s), and no & but plain ones (as &amp;).
        const link = m.match(/^<a\s+href=("|')(https?:\/\/[^"'\s<>]+)\1\s*>$/i);
        const url = link ? link[2].replace(/&(?!(?:[a-z][a-z0-9]*|#[0-9]+|#x[0-9a-f]+);)/gi, "&amp;") : "";
        if (/^https?:\/\/(?:[^"'\s&<>]|&amp;)+$/i.test(url))
            return keep('<a href="' + url + '">');
        return "";
    });
    // A lone & (not an entity like &amp;) is text.
    s = s.replace(/&(?!(?:[a-z][a-z0-9]*|#[0-9]+|#x[0-9a-f]+);)/gi, "&amp;");
    s = s.replace(/</g, "&lt;").replace(/>/g, "&gt;");
    return s.replace(/\uE000(\d+)\uE001/g, (m, i) => kept[Number(i)] ?? "");
}
