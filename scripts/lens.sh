#!/bin/sh
# Search a picture (or a part of it) with Google Lens, in the default
# browser.
#   lens.sh <picture.png> <geometry or "">
# geometry: WxH+X+Y in the picture's pixels ("" = all of it).
#
# The picture goes to Google and nowhere else: no file host in between
# (end-4's way, uguu.se + lens.google.com/uploadbyurl, hands it to a public
# host first). Here a small page, written to $XDG_RUNTIME_DIR (yours only,
# gone at logout), holds the picture; the browser opens it and the page
# posts the picture straight to Lens (lens.google.com/v3/upload, field
# encoded_image), the way Chrome's "Search with Google Lens" does. Google
# answers with the results page, in your browser, with your Google
# settings. The page is deleted a minute later (the browser has read it).
# SumatraPDF and others do the same. If Google moves the upload, only
# $url and the field name below change.
#
# Prints the page's path. MINE_SHOT_DRYRUN=1 (tests): the browser isn't
# opened (the command is printed) and the page is kept; MINE_LENS_DIR: the
# page goes there; MINE_LENS_URL: posts there instead (a test server);
# MINE_LENS_KEEP: seconds until the page is deleted (60).
picture="$1"
geometry="$2"
url="${MINE_LENS_URL:-https://lens.google.com/v3/upload}"

dir="${MINE_LENS_DIR:-${XDG_RUNTIME_DIR:-/tmp}/mine-lens}"
mkdir -p -m 700 "$dir" || exit 1
stamp=$(date +%s%3N)
image="$dir/lens-$stamp.jpg"
page="$dir/lens-$stamp.html"
trap 'rm -f "$image"' EXIT

# Read as PNG, under ../magick/policy.xml (see ocr.sh). At most 1600 px
# on a side, as JPEG: what Lens works with anyway, and a light page.
MAGICK_CONFIGURE_PATH=$(cd "$(dirname -- "$0")/.." && pwd)/magick
export MAGICK_CONFIGURE_PATH
crop=""
[ -n "$geometry" ] && crop="-crop $geometry +repage"
# shellcheck disable=SC2086
magick "png:$picture" $crop -resize '1600x1600>' -quality 90 "jpeg:$image" || exit 1
size=$(magick identify -format '%w,%h' "jpeg:$image") || exit 1

# The page: a form posting the picture to Lens, sent by itself. The
# picture is in the page (base64), put into the form's file field with
# DataTransfer. No referrer, nothing else loaded (the CSP); where the form
# may go isn't limited there, as that would also stop Google's redirect
# to the results.
umask 077
{
    cat <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="referrer" content="no-referrer">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'">
<title>Google Lens</title>
<style>
  html { color-scheme: light dark; }
  body { margin: 0; height: 100vh; display: grid; place-items: center; font: 15px system-ui, sans-serif; opacity: 0.7; }
</style>
</head>
<body>
<p id="say">Opening Google Lens…</p>
<form id="lens" method="post" enctype="multipart/form-data" action="$url?ep=ccm&amp;s=&amp;st=$stamp">
<input id="image" type="file" name="encoded_image" hidden>
<input type="hidden" name="processed_image_dimensions" value="$size">
</form>
<script>
EOF
    # On one line: a JS string can't hold a line break.
    printf 'const picture = "'
    base64 -w 0 "$image"
    printf '";\n'
    cat <<'EOF'
try {
  const bytes = Uint8Array.from(atob(picture), c => c.charCodeAt(0));
  const files = new DataTransfer();
  files.items.add(new File([bytes], "screenshot.jpg", { type: "image/jpeg" }));
  document.getElementById("image").files = files.files;
  document.getElementById("lens").submit();
} catch (e) {
  document.getElementById("say").textContent = "Couldn't send the picture to Google Lens: " + e;
}
</script>
</body>
</html>
EOF
} > "$page" || exit 1
echo "$page"

if [ "$MINE_SHOT_DRYRUN" = 1 ]; then
    echo "lens (dry run): xdg-open file://$page" >&2
    exit 0
fi
setsid -f xdg-open "file://$page" >/dev/null 2>&1 || exit 1
# Gone once the browser has read it.
setsid -f sh -c 'sleep "$1"; rm -f "$2"' sh "${MINE_LENS_KEEP:-60}" "$page" >/dev/null 2>&1
exit 0
