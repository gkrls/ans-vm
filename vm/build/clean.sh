#!/bin/bash
set -e

# Easiest use:
#  Copy this to share, ssh into the vm and run it
#  When done copy it back here and run manuall the command at the bottom

echo "[1] Removing package caches..."
sudo apt clean
# sudo apt autoremove -y

echo "[2] Clearing logs..."
sudo journalctl --rotate
sudo journalctl --vacuum-time=1s
sudo find /var/log -type f -exec sudo truncate -s 0 {} \;

echo "[3] Zeroing free disk space..."
sudo dd if=/dev/zero of=/EMPTY bs=1M status=progress 2>/dev/null || true
sudo rm -f /EMPTY
sync

echo "Done."

# Then do:
# cat /dev/null > ~/.bash_history && sudo tee /root/.bash_history < /dev/null && history -c