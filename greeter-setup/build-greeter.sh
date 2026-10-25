#!/bin/bash
# Builds the login screen's own folder from the shell:
#   build-greeter.sh <shell folder> <your home> <destination>
# Copies greeter.qml, greeter/, common/, lock/ (it shows the mac style),
# run-greeter.sh, and the fonts the greeter can't read from your
# home folder (Google Sans Flex, SF Pro Rounded). Used by greeter-install.sh
# and the tests; touches nothing outside <destination>.
set -eu

src=$1
home=$2
dest=$3
here=$(cd "$(dirname "$0")" && pwd)

[ -f "$src/greeter.qml" ] || { echo "build-greeter: no greeter.qml in $src" >&2; exit 1; }

# Only real files go into the folder root runs the login screen from. A
# link in your tree (to /etc/shadow, or to QML of yours somewhere else) would
# be copied as what it points at, made readable to all, or kept as a link
# the login screen follows. None is ever needed, so any one stops the build.
links=$(find "$src/greeter.qml" "$src/greeter" "$src/common" "$src/lock" "$here/run-greeter.sh" -type l 2>/dev/null)
if [ -n "$links" ]; then
    echo "build-greeter: links in the shell folder, not built:" >&2
    echo "$links" >&2
    exit 1
fi

rm -rf "$dest"
mkdir -p "$dest/lock" "$dest/fonts"
cp -P "$src/greeter.qml" "$dest/"
cp -rP "$src/greeter" "$src/common" "$dest/"
# All of lock/, not a list of the parts MacView uses: a new part missing from
# such a list made the login screen fail to load (a black screen at boot).
# Parts it doesn't use cost nothing; QML only reads the ones a screen uses.
cp -P "$src"/lock/*.qml "$dest/lock/"
cp -P "$here/run-greeter.sh" "$dest/run-greeter.sh"

# Fonts (only these two families; the icon font is system-wide already).
fonts=$home/.local/share/fonts
find "$fonts" -type f \( -name 'GoogleSansFlex*.ttf' -o -name 'SF-Pro-Rounded-*.otf' \) \
    -exec cp -P {} "$dest/fonts/" \; 2>/dev/null || true
# (A font swapped for a link between find and cp would be copied as a link:
# none goes in.)
find "$dest/fonts" -type l -delete

# Does it load? Started off screen for a few seconds, as the greeter user
# when there is one: a missing part or a typo stops it at once ("Failed to
# load configuration"), still running at the end means it loaded. A login
# screen that doesn't load is a black screen at boot, so it's not built.
check=$(mktemp -d)
as=()
if [ "$(id -u)" = 0 ] && id greeter >/dev/null 2>&1; then
    chown greeter: "$check"
    as=(runuser -u greeter --)
fi
set +e
"${as[@]}" env -i PATH=/usr/bin HOME="$check" XDG_RUNTIME_DIR="$check" \
    XDG_CACHE_HOME="$check/cache" XDG_STATE_HOME="$check/state" \
    QT_QPA_PLATFORM=offscreen MINE_GREETER_DRYRUN=1 \
    timeout 5 /usr/bin/qs -p "$dest/greeter.qml" > "$check/log" 2>&1
status=$?
set -e
if [ "$status" != 124 ]; then
    echo "build-greeter: the login screen doesn't load (qs exit $status):" >&2
    grep -aE 'ERROR|caused by' "$check/log" | sed 's/\x1b\[[0-9;]*m//g' >&2
    rm -rf "$check" "$dest"
    exit 1
fi
rm -rf "$check"

echo "build-greeter: $(find "$dest" -name '*.qml' | wc -l) qml files, $(ls "$dest/fonts" | wc -l) fonts, loads → $dest"
