#!/bin/bash
# Takes face unlock away again: the lock screen's face check (it stops
# looking as soon as /etc/pam.d/mine-face is gone), your face model, Howdy
# and dlib. What pacman installed with them goes too (-Rns asks first).
#   sudo bash ~/.config/quickshell/mine/setup/face-undo.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }

rm -f /etc/pam.d/mine-face
rm -rf /etc/howdy/models
pkgs=$(pacman -Qq howdy-git python-dlib 2>/dev/null || true)
[ -n "$pkgs" ] && pacman -Rns $pkgs
rm -rf /etc/howdy
echo "Done: the lock screen asks for the password only."
