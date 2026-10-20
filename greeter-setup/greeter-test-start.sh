#!/bin/bash
# Step 2: the new login screen on VT 7, next to your session, without
# touching GDM. Press Ctrl+Alt+F7 to see it, Ctrl+Alt+F2 to come back.
# Typing the right password only shows "Password OK (test mode)".
# Afterwards: sudo bash greeter-test-stop.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }
grep -q '^vt = 7' /etc/greetd/config.toml || {
    echo "/etc/greetd/config.toml isn't the test setup (vt = 7); run greeter-install.sh first."
    exit 1
}
echo "==> Starting greetd on VT 7 (not enabled; it won't come back after a reboot)"
systemctl start greetd.service
sleep 1
systemctl --no-pager --lines=5 status greetd.service || true
echo
echo "Press Ctrl+Alt+F7 to try it. Ctrl+Alt+F2 brings you back here."
echo "If it looks wrong: sudo cat /var/cache/mine-greeter/greeter.log"
