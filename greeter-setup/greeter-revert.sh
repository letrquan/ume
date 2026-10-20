#!/bin/bash
# Back to GDM as the login screen (from the next boot). Works from a text
# console: Ctrl+Alt+F3, log in, then
#   sudo bash ~/greeter-revert.sh && sudo reboot
# The new login screen stays installed (/etc/greetd), just not used.
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }
echo "==> greetd off"
systemctl disable greetd.service 2>/dev/null || true
echo "==> GDM on"
systemctl enable gdm.service
if [ -f /etc/pam.d/greetd.mine-backup ]; then
    echo "==> /etc/pam.d/greetd back to the package's"
    cp -p /etc/pam.d/greetd.mine-backup /etc/pam.d/greetd
fi
if [ -f /etc/greetd/config.toml.mine-backup ]; then
    echo "==> /etc/greetd/config.toml back to the package's"
    cp -p /etc/greetd/config.toml.mine-backup /etc/greetd/config.toml
fi
systemctl is-enabled gdm.service
echo
echo "Done. Reboot (sudo reboot) and GDM is back."
