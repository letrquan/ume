#!/bin/bash
# Face unlock for the lock screen, with the laptop's IR camera (the one
# Windows Hello uses) and Howdy. Only the lock screen:
#   - the login screen keeps the password: it's what unlocks your saved
#     passwords (the keyring);
#   - sudo and admin popups keep the password: any program you run, an AI
#     agent too, could ask for them, and your face would say yes for it
#     just because you're sitting there.
# What it does:
#   1. a snapper snapshot,
#   2. installs Howdy and dlib, built in ~/.cache/mine-dev/face-build (no
#      CUDA, no Howdy popup window, polkit left alone), plus what they need
#      from the repos (python-opencv and friends; pacman lists them),
#   3. points Howdy at the IR camera,
#   4. writes /etc/pam.d/mine-face: your face only, used by the lock screen
#      (lock.qml) and nothing else,
#   5. learns your face (look at the camera),
#   6. checks it the way the lock screen will: as you, not as root.
# Undo: sudo bash face-undo.sh (next to this file).
#   sudo bash ~/.config/quickshell/mine/setup/face-setup.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }
user=${SUDO_USER:-}
[ -n "$user" ] && [ "$user" != root ] || { echo "Run it with sudo from your own account."; exit 1; }
home=$(getent passwd "$user" | cut -d: -f6)
build=$home/.cache/mine-dev/face-build
dlib=$(ls -t "$build"/python-dlib/python-dlib-*.pkg.tar.zst 2>/dev/null | head -n 1)
howdy=$(ls -t "$build"/howdy-git/howdy-git-*.pkg.tar.zst 2>/dev/null | head -n 1)
[ -n "$dlib" ] && [ -n "$howdy" ] || { echo "The packages aren't built yet (in $build)."; exit 1; }

# The IR camera: the video device called "… IR Camera", its first node,
# by its USB port (stays the same when the numbers change).
ir=""
for dev in /sys/class/video4linux/video*; do
    grep -q "IR Camera" "$dev/name" 2>/dev/null || continue
    [ "$(cat "$dev/index" 2>/dev/null)" = 0 ] || continue
    for link in /dev/v4l/by-path/*; do
        case $link in *usbv2*) continue ;; esac
        if [ "$(readlink -f "$link")" = "/dev/$(basename "$dev")" ]; then
            ir=$link
            break
        fi
    done
    [ -n "$ir" ] && break
done
[ -n "$ir" ] || { echo "No IR camera found."; exit 1; }
echo "IR camera: $ir ($(readlink -f "$ir"))"

if snapper list-configs 2>/dev/null | grep -q '^root '; then
    echo "==> Snapshot"
    snapper -c root create -d "before face-setup (mine)"
fi

echo "==> Installing Howdy (pacman lists what comes with it: say yes)"
pacman -U --needed "$dlib" "$howdy"

echo "==> Pointing Howdy at the IR camera"
cfg=/etc/howdy/config.ini
sed -i -E "s|^device_path *=.*|device_path = $ir|" "$cfg"
# No "Identified face as …": the lock screen shows it its own way.
sed -i -E "s|^no_confirmation *=.*|no_confirmation = true|" "$cfg"
grep -E '^(device_path|no_confirmation|timeout|dark_threshold|certainty) ' "$cfg"

echo "==> /etc/pam.d/mine-face (the lock screen's face check)"
cat > /etc/pam.d/mine-face <<'EOF'
#%PAM-1.0
# Face unlock for the mine lock screen ONLY: lock.qml's second PAM
# conversation, beside the password one on "login". Written by
# setup/face-setup.sh; nothing else uses it. Your face or nothing: a failed
# look never falls through to a password and never counts toward faillock.
auth     sufficient  pam_howdy.so
auth     required    pam_deny.so
account  required    pam_unix.so
EOF
chmod 644 /etc/pam.d/mine-face

echo "==> Learning your face: look at the camera, about 40 cm away"
howdy -U "$user" -y add
# The lock screen runs as you, so it must be able to read your face model
# (only you and root can).
chmod 755 /etc/howdy/models
chown root:"$(id -gn "$user")" "/etc/howdy/models/$user.dat"
chmod 640 "/etc/howdy/models/$user.dat"

echo "==> Checking it like the lock screen will (as $user): look at the camera"
set +e
runuser -u "$user" -- /usr/bin/python /usr/lib/howdy/compare.py "$user"
status=$?
set -e
case $status in
    0) echo "OK: it knows your face. To try it: lock the screen (Super+Alt+L), wait"
       echo "a few seconds, then move the mouse or press a key and look at the camera." ;;
    11) echo "It didn't recognize you in time. Run this again in better light, or add"
        echo "another look:  sudo howdy -U $user add" ;;
    13) echo "The camera's pictures were too dark (dark_threshold in $cfg)." ;;
    14) echo "Howdy couldn't open the camera ($ir)." ;;
    *) echo "The check ended with $status (Howdy's codes: 10 no face model, 12 aborted)." ;;
esac
