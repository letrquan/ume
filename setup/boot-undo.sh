#!/bin/bash
# Puts back what boot-setup.sh changed (from /etc/mine-boot-backup): GRUB's
# menu and its text, the kernel's messages, the CachyOS boot animation. The
# login screen's fade-in stays (it's part of the login screen's code).
#   sudo bash ~/.config/quickshell/mine/setup/boot-undo.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }
bak=/etc/mine-boot-backup
[ -d "$bak" ] || { echo "Nothing to undo (no $bak)."; exit 1; }

[ -e "$bak/grub" ] && cp -a "$bak/grub" /etc/default/grub
[ -e "$bak/10_linux" ] && cat "$bak/10_linux" > /etc/grub.d/10_linux
[ -e "$bak/plymouthd.conf" ] && cp -a "$bak/plymouthd.conf" /etc/plymouth/plymouthd.conf

echo "==> GRUB: writing /boot/grub/grub.cfg"
grub-mkconfig -o /boot/grub/grub.cfg
echo "==> Rebuilding the boot images"
mkinitcpio -P
rm -rf "$bak"
echo "Done: back to how it was. It shows at the next reboot."
