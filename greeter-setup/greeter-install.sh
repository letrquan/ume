#!/bin/bash
# Step 1 of the new login screen: installs it, but does NOT turn it on.
# GDM stays your login screen. Run:
#   sudo bash ~/.config/quickshell/mine/greeter-setup/greeter-install.sh
# Then test it on VT 7 (greeter-test-start.sh), then switch
# (greeter-switch.sh). Back: greeter-revert.sh. Safe to run again (it
# updates the login screen's copy of the shell).
set -eu

[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }
user=${SUDO_USER:-}
if [ -z "$user" ] || [ "$user" = root ]; then
    echo "Run it with sudo from your own account (it needs to know who you are)."
    exit 1
fi
home=$(getent passwd "$user" | cut -d: -f6)
group=$(id -gn "$user")
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/.." && pwd)
step() { echo; echo "==> $*"; }

step "Installing greetd and cage (GDM stays installed and in use)"
pacman -S --needed --noconfirm greetd cage
id greeter >/dev/null 2>&1 || systemd-sysusers
id greeter >/dev/null 2>&1 || { echo "No 'greeter' user after installing greetd; stopping."; exit 1; }
# cage needs the screen; logind gives it to the active session, the group
# is a fallback.
usermod -aG video greeter

step "Copying the login screen to /etc/greetd/mine-greeter (owned by root)"
bash "$here/build-greeter.sh" "$src" "$home" /etc/greetd/mine-greeter.new
rm -rf /etc/greetd/mine-greeter.old
[ -d /etc/greetd/mine-greeter ] && mv /etc/greetd/mine-greeter /etc/greetd/mine-greeter.old
mv /etc/greetd/mine-greeter.new /etc/greetd/mine-greeter
chown -R root:root /etc/greetd/mine-greeter
find /etc/greetd/mine-greeter -type d -exec chmod 755 {} +
find /etc/greetd/mine-greeter -type f -exec chmod 644 {} +
chmod 755 /etc/greetd/mine-greeter/run-greeter.sh
rm -rf /etc/greetd/mine-greeter.old

step "Folders: /var/lib/mine-greeter (yours, others can read) and /var/cache/mine-greeter (the greeter's only)"
install -d -o "$user" -g "$group" -m 755 /var/lib/mine-greeter
install -d -o greeter -g greeter -m 700 /var/cache/mine-greeter
install -d -o greeter -g greeter -m 700 /var/cache/mine-greeter/cache

step "Copying your wallpaper, colors and picture there (as $user)"
sudo -u "$user" env HOME="$home" sh "$src/scripts/greeter-sync.sh"
ls -l /var/lib/mine-greeter

step "PAM: /etc/pam.d/greetd with gnome-keyring, like GDM's"
if [ ! -f /etc/pam.d/greetd.mine-backup ]; then
    cp -p /etc/pam.d/greetd /etc/pam.d/greetd.mine-backup
    echo "package version kept as /etc/pam.d/greetd.mine-backup"
fi
# (Real files only: install would copy what a link points at.)
[ ! -L "$here/greetd.pam" ] && [ ! -L "$here/config-test.toml" ] || { echo "greetd.pam or config-test.toml is a link; not installing."; exit 1; }
install -m 644 "$here/greetd.pam" /etc/pam.d/greetd

step "greetd settings: TEST mode on VT 7 (not enabled, not started)"
if [ ! -f /etc/greetd/config.toml.mine-backup ]; then
    cp -p /etc/greetd/config.toml /etc/greetd/config.toml.mine-backup
fi
install -m 644 "$here/config-test.toml" /etc/greetd/config.toml

step "Boot splash: greetd waits for plymouth to finish"
if systemctl cat greetd.service | grep -q 'plymouth-quit-wait'; then
    echo "greetd.service already orders after plymouth-quit-wait.service"
else
    install -d /etc/systemd/system/greetd.service.d
    printf '[Unit]\nAfter=plymouth-quit-wait.service\n' > /etc/systemd/system/greetd.service.d/plymouth.conf
    echo "added /etc/systemd/system/greetd.service.d/plymouth.conf"
fi
systemctl daemon-reload

step "Done. GDM is still your login screen."
echo "Next: sudo bash $here/greeter-test-start.sh, then press Ctrl+Alt+F7."
