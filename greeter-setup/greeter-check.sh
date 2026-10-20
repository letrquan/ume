#!/bin/bash
# No sudo: builds the login screen from this shell folder into a temporary
# folder, checks that it loads, and says whether the installed one
# (/etc/greetd/mine-greeter) is older. Run it after changing greeter/,
# common/ or lock/, before greeter-update.sh.
#   bash ~/.config/quickshell/mine/greeter-setup/greeter-check.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! bash "$here/build-greeter.sh" "$src" "$HOME" "$tmp/greeter" > /dev/null; then
    echo "NOT OK: fix this before running greeter-update.sh (it would refuse anyway)."
    exit 1
fi
echo "OK: the login screen loads."

if [ ! -d /etc/greetd/mine-greeter ]; then
    echo "Not installed (greeter-install.sh)."
elif diff -rq "$tmp/greeter" /etc/greetd/mine-greeter > /dev/null 2>&1; then
    echo "The installed login screen is up to date."
else
    echo "The installed login screen is older. To update it:"
    echo "  sudo bash $here/greeter-update.sh"
fi
