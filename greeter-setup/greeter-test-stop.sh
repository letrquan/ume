#!/bin/bash
# Ends the VT 7 test. GDM and your session are untouched.
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }
echo "==> Stopping greetd"
systemctl stop greetd.service
echo "Stopped. What the login screen printed: sudo cat /var/cache/mine-greeter/greeter.log"
