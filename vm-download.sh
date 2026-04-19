#!/bin/bash
#  Download the prebuilt VM image.
#
#  Usage:
#   ./vm-download.sh           Auto-detect (qemu on ARM Mac, vbox elsewhere)
#   ./vm-download.sh --qemu    Force QEMU image
#   ./vm-download.sh --vbox    Force VBox image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$SCRIPT_DIR/vm"

QCOW2_URL="https://surfdrive.surf.nl/s/jPAWBPLt5g8p43g/download"
OVA_URL="https://surfdrive.surf.nl/s/LFetRd83HR4Csdx/download"

# --- Parse args ---
BACKEND=""
for arg in "$@"; do
    case "$arg" in
        --qemu) BACKEND=qemu ;;
        --vbox) BACKEND=vbox ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

# --- Autodetect ---
if [ -z "$BACKEND" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) BACKEND=qemu ;;
        *)            BACKEND=vbox ;;
    esac
fi

mkdir -p "$VM_DIR"

if [ "$BACKEND" = "qemu" ]; then
    OUT="$VM_DIR/ans.qcow2"
    URL="$QCOW2_URL"
else
    OUT="$VM_DIR/ans.ova"
    URL="$OVA_URL"
fi

if [ -f "$OUT" ]; then
    read -p "$OUT already exists. Overwrite? (y/N) " -r
    [[ ! $REPLY =~ ^[Yy]$ ]] && echo "Aborted." && exit 0
fi

echo "Downloading $BACKEND image..."
echo "  From: $URL"
echo "  To:   $OUT"
echo ""

if command -v curl &>/dev/null; then
    curl -L --fail -o "$OUT" "$URL"
elif command -v wget &>/dev/null; then
    wget -O "$OUT" "$URL"
else
    echo "ERROR: neither curl nor wget is installed."
    exit 1
fi

echo ""
echo "Done. Next: ./vm-start.sh"