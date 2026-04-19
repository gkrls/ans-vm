#!/bin/bash
# ─────────────────────────────────────────────
#  Install Dependencies
#  Usage: ./install_deps.sh
# ─────────────────────────────────────────────

set -e

OS="$(uname -s)"
case "$OS" in
    Linux)
        echo "Installing QEMU and tools..."
        sudo apt-get update -qq
        sudo apt-get install -y qemu-system-x86 qemu-utils genisoimage
        ;;
    Darwin)
        if ! command -v brew &>/dev/null; then
            echo "ERROR: Homebrew not found. Install from https://brew.sh"
            exit 1
        fi
        export HOMEBREW_NO_AUTO_UPDATE=1

        command -v qemu-system-x86_64 &>/dev/null || brew install qemu
        command -v mkisofs &>/dev/null || brew install cdrtools

        if [ ! -d /Applications/Utilities/XQuartz.app ]; then
            brew install --cask xquartz 2>/dev/null || echo "Install XQuartz manually: https://www.xquartz.org"
        fi
        ;;
    *) echo "Unsupported OS"; exit 1 ;;
esac

echo "Done: $(qemu-system-x86_64 --version | head -1)"