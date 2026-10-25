#!/bin/bash
# Step 3: make the new login screen THE login screen (instead of GDM), from
# the next boot. Your session keeps running; nothing is stopped now.
# Before rebooting, make sure you can get back: Ctrl+Alt+F3 gives a text
# login, where `sudo bash ~/greeter-revert.sh` puts GDM back.
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
[ -x /etc/greetd/mine-greeter/run-greeter.sh ] || { echo "Run greeter-install.sh first."; exit 1; }

echo "==> Stopping the VT 7 test, if it's running"
systemctl stop greetd.service 2>/dev/null || true

echo "==> greetd settings: the real thing (VT 1, no test mode)"
[ ! -L "$here/config-real.toml" ] || { echo "config-real.toml is a link; not installing."; exit 1; }
install -m 644 "$here/config-real.toml" /etc/greetd/config.toml

echo "==> GDM off at boot, greetd on (GDM keeps running until you reboot)"
systemctl disable gdm.service
if ! systemctl enable greetd.service; then
    echo "!! enabling greetd failed: putting GDM back"
    systemctl enable gdm.service
    exit 1
fi
systemctl is-enabled greetd.service
echo
echo "Done. Reboot when ready. If the new login screen doesn't work:"
echo "  Ctrl+Alt+F3, log in, then: sudo bash ~/greeter-revert.sh && sudo reboot"
