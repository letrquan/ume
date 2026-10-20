#!/bin/bash
# Updates only the login screen's code in /etc/greetd/mine-greeter (from
# this shell folder). Leaves greetd's settings, PAM and GDM alone. The new
# version shows the next time the login screen starts (log out, or reboot).
#   sudo bash ~/.config/quickshell/mine/greeter-setup/greeter-update.sh
# --restart also restarts greetd now: ONLY from a text login whose desktop
# wasn't started by greetd (restarting it would end that desktop).
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }
user=${SUDO_USER:-}
[ -n "$user" ] && [ "$user" != root ] || { echo "Run it with sudo from your own account."; exit 1; }
home=$(getent passwd "$user" | cut -d: -f6)
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/.." && pwd)
[ -d /etc/greetd/mine-greeter ] || { echo "Not installed yet: run greeter-install.sh first."; exit 1; }

echo "==> Copying the login screen to /etc/greetd/mine-greeter"
bash "$here/build-greeter.sh" "$src" "$home" /etc/greetd/mine-greeter.new \
    || { echo "Nothing changed: the login screen you have stays."; exit 1; }
rm -rf /etc/greetd/mine-greeter.old
mv /etc/greetd/mine-greeter /etc/greetd/mine-greeter.old
mv /etc/greetd/mine-greeter.new /etc/greetd/mine-greeter
chown -R root:root /etc/greetd/mine-greeter
find /etc/greetd/mine-greeter -type d -exec chmod 755 {} +
find /etc/greetd/mine-greeter -type f -exec chmod 644 {} +
chmod 755 /etc/greetd/mine-greeter/run-greeter.sh
rm -rf /etc/greetd/mine-greeter.old

# Also when it gave up (a login screen that kept failing: "start-limit-hit").
if [ "${1:-}" = "--restart" ] && systemctl is-enabled --quiet greetd.service; then
    echo "==> Restarting the login screen"
    systemctl reset-failed greetd.service
    systemctl restart greetd.service
    echo "Done."
else
    echo "Done. The new login screen shows next time (log out or reboot)."
fi
