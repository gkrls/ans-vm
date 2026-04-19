#!/bin/bash
#  Stop the running VM.
#
#  Usage:
#   ./vm-stop.sh                Auto-detect backend
#   ./vm-stop.sh --qemu         Force QEMU
#   ./vm-stop.sh --vbox         Force VirtualBox

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="ans"

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

if [ "$BACKEND" = "vbox" ]; then
    if ! VBoxManage list runningvms | grep -q "\"$VM_NAME\""; then
        echo "VM '$VM_NAME' is not running."
        exit 0
    fi
    echo "Stopping VM..."
    VBoxManage controlvm "$VM_NAME" acpipowerbutton
    # Wait up to 30s for graceful shutdown
    for i in {1..30}; do
        VBoxManage list runningvms | grep -q "\"$VM_NAME\"" || { echo "Stopped."; exit 0; }
        sleep 1
    done
    echo "Graceful shutdown timed out. Forcing poweroff..."
    VBoxManage controlvm "$VM_NAME" poweroff
else
    # QEMU runs in foreground — Ctrl+C in vm-start.sh window stops it
    echo "For QEMU, stop the VM with Ctrl+C in the terminal running vm-start.sh."
    exit 0
fi