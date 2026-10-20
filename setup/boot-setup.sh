#!/bin/bash
# A cleaner boot, like a Mac's: the HP logo from power on to the login screen.
#   - GRUB's menu is hidden. It waits 1 s: tap Esc (or hold Shift) right
#     after the HP logo to get it, with the other kernels and the restore
#     snapshots, as before.
#   - No "Loading Linux …" lines from GRUB, and a quiet kernel ("quiet").
#   - The boot animation: the HP logo with a small spinner under it
#     (Plymouth's bgrt theme) instead of the CachyOS one.
#   - The login screen fades in from black (greeter-update.sh).
# The files it changes are copied first to /etc/mine-boot-backup; a snapper
# snapshot is taken too. Undo: sudo bash boot-undo.sh (next to this file).
#   sudo bash ~/.config/quickshell/mine/setup/boot-setup.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }
[ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ] || { echo "Run it with sudo from your own account."; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)

grub=/etc/default/grub
linux=/etc/grub.d/10_linux
plymouth=/etc/plymouth/plymouthd.conf
bak=/etc/mine-boot-backup

# Only the first run copies: running it again keeps the real originals.
mkdir -p "$bak"
[ -e "$bak/grub" ] || cp -a "$grub" "$bak/grub"
[ -e "$bak/10_linux" ] || cp -a "$linux" "$bak/10_linux"
[ -e "$bak/plymouthd.conf" ] || cp -a "$plymouth" "$bak/plymouthd.conf"

if snapper list-configs 2>/dev/null | grep -q '^root '; then
    echo "==> Snapshot"
    snapper -c root create -d "before boot-setup (mine)"
fi

echo "==> GRUB: menu hidden (Esc shows it), quiet"
sed -i -E "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT='1'/; s/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/" "$grub"
grep -qE "^GRUB_CMDLINE_LINUX_DEFAULT=.*[' ]quiet[' ]" "$grub" ||
    sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT='[^']*)'/\1 quiet'/" "$grub"
grep -E '^GRUB_(TIMEOUT|TIMEOUT_STYLE|CMDLINE_LINUX_DEFAULT)=' "$grub"
grep -qE "^GRUB_CMDLINE_LINUX_DEFAULT=.*[' ]quiet[' ]" "$grub" ||
    echo "   (couldn't add quiet: the line isn't in single quotes; the rest still applies)"

# The two "Loading …" lines GRUB writes for each kernel. 10_linux belongs to
# the grub package: an update puts them back (harmless, just the text).
line=$'\techo\t'"'"'$(echo "$message" | grub_quote)'"'"
found=$(grep -cxF "$line" "$linux" || true)
if [ "$found" -gt 0 ]; then
    grep -vxF "$line" "$linux" > "$linux.new"
    cat "$linux.new" > "$linux"      # keeps the file's mode (it must stay executable)
    rm -f "$linux.new"
    echo "   removed $found \"Loading …\" lines"
fi

echo "==> GRUB: writing /boot/grub/grub.cfg"
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Boot animation: the HP logo (bgrt); rebuilding the boot images of all 3 kernels"
sed -i -E 's/^Theme=.*/Theme=bgrt/' "$plymouth"
grep -q '^Theme=bgrt' "$plymouth" || printf '[Daemon]\nTheme=bgrt\n' >> "$plymouth"
if ! mkinitcpio -P; then
    echo
    echo "!! mkinitcpio failed (above). Don't reboot: run  sudo bash $here/boot-undo.sh"
    exit 1
fi

echo "==> Login screen: fades in"
bash "$here/../greeter-setup/greeter-update.sh"

echo
echo "Done. Reboot to see it. Right after the HP logo, tap Esc once to check"
echo "that GRUB's menu still comes up (then pick the first entry)."
