#!/bin/bash
#  Usage:
#   ./vm-start.sh                Auto-detect backend
#   ./vm-start.sh --qemu         Force QEMU
#   ./vm-start.sh --vbox         Force VirtualBox
#   ./vm-start.sh --debug        With a window
#   (flags combine: ./vm-start.sh --qemu --debug)
#
#  Connect: ./vm-connect.sh
#  Stop:    Ctrl+C (qemu) or ./vm-stop.sh (vbox)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$SCRIPT_DIR/vm"
SHARE="$SCRIPT_DIR/share"
SSH_PORT=2222
RAM=8192
CPUS=4
VM_NAME="ans"

mkdir -p "$SHARE"

# --- Parse args ---
BACKEND=""
DEBUG=0
for arg in "$@"; do
    case "$arg" in
        --qemu)  BACKEND=qemu ;;
        --vbox)  BACKEND=vbox ;;
        --debug) DEBUG=1 ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

# --- Platform detection / backend validation ---
HOST="$(uname -s)-$(uname -m)"

if [ -z "$BACKEND" ]; then
    case "$HOST" in
        Darwin-arm64)                           BACKEND=qemu ;;
        Linux-*|Darwin-*|MINGW*|MSYS*|CYGWIN*)  BACKEND=vbox ;;
        *) echo "Unsupported platform: $HOST"; exit 1 ;;
    esac
else
    case "$BACKEND-$HOST" in
        qemu-Linux-*|qemu-Darwin-*) : ;;
        vbox-Linux-*|vbox-Darwin-x86_64|vbox-MINGW*|vbox-MSYS*|vbox-CYGWIN*) : ;;
        vbox-Darwin-arm64)
            echo "ERROR: VirtualBox is not supported on Apple Silicon. Use --qemu."
            exit 1 ;;
        qemu-MINGW*|qemu-MSYS*|qemu-CYGWIN*)
            echo "ERROR: QEMU is not supported on Windows here. Use --vbox."
            exit 1 ;;
        *) echo "ERROR: $BACKEND not supported on $HOST"; exit 1 ;;
    esac
fi

echo "Backend: $BACKEND"

# ============================================================
# QEMU
# ============================================================
if [ "$BACKEND" = "qemu" ]; then
    QCOW2="$VM_DIR/ans.qcow2"
    [ ! -f "$QCOW2" ] && { echo "ERROR: $QCOW2 not found. Run ./download.sh --qemu"; exit 1; }

    case "$HOST" in
        Darwin-*)
            [ ! -d /Applications/Utilities/XQuartz.app ] && { echo "ERROR: XQuartz not installed."; exit 1; }
            pgrep -q Xquartz || { open -a XQuartz; sleep 2; }
            if [ "$(uname -m)" = "arm64" ]; then
                ACCEL="-accel tcg"            # x86 on ARM — slow
            else
                ACCEL="-accel hvf -cpu Haswell,check=off"
            fi
            GUI="-display cocoa,zoom-to-fit=on"
            ;;
        Linux-*)
            [ -e /dev/kvm ] && ACCEL="-accel kvm -cpu host" || ACCEL="-accel tcg"
            GUI="-display gtk,zoom-to-fit=on"
            ;;
    esac

    if [ $DEBUG -eq 1 ]; then
        DISPLAY_FLAG="$GUI"
        echo "Starting VM (debug window, QEMU)..."
    else
        DISPLAY_FLAG="-display none"
        echo "Starting VM (headless, QEMU)..."
    fi
    echo "  Connect: ./vm-connect.sh"
    echo "  Stop:    Ctrl+C"
    echo ""

    exec qemu-system-x86_64 \
        $ACCEL \
        -m $RAM -smp $CPUS \
        -drive file="$QCOW2",if=virtio,format=qcow2,cache=writeback,aio=threads \
        -nic user,hostfwd=tcp::${SSH_PORT}-:22 \
        -virtfs local,path="$SHARE",mount_tag=hostshare,security_model=none,id=hostshare \
        -rtc base=utc,clock=host \
        $DISPLAY_FLAG
fi

# ============================================================
# VirtualBox
# ============================================================
if [ "$BACKEND" = "vbox" ]; then
    OVA="$VM_DIR/ans.ova"

    # Reimport if the .ova is newer than the registered VM
    if VBoxManage showvminfo "$VM_NAME" &>/dev/null && [ -f "$OVA" ]; then
        VM_CFG=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep CfgFile= | cut -d'"' -f2)
        if [ -n "$VM_CFG" ] && [ "$OVA" -nt "$VM_CFG" ]; then
            echo "New image detected. Reimporting..."
            VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
            VBoxManage unregistervm "$VM_NAME" --delete
        fi
    fi

    if ! VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
        [ ! -f "$OVA" ] && { echo "ERROR: $OVA not found. Run ./download.sh --vbox"; exit 1; }
        echo "First run: importing $OVA..."
        VBoxManage import "$OVA" --vsys 0 --vmname "$VM_NAME"
    fi

    # Always apply resource settings
    VBoxManage modifyvm "$VM_NAME" --memory $RAM --cpus $CPUS
    
    # Add port forward if not already set
    if ! VBoxManage showvminfo ans | grep -q "host port = 2222"; then
        VBoxManage modifyvm ans --natpf1 "ssh,tcp,,2222,,22"
    fi

    # Add shared folder if not already set
    if ! VBoxManage showvminfo "$VM_NAME" | grep -q "hostshare"; then
        VBoxManage sharedfolder add "$VM_NAME" --name hostshare --hostpath "$SHARE"
    fi

    if VBoxManage list runningvms | grep -q "\"$VM_NAME\""; then
        echo "VM '$VM_NAME' already running."
        echo "  Connect: ./vm-connect.sh"
        exit 0
    fi

    if [ $DEBUG -eq 1 ]; then
        TYPE="gui"
        echo "Starting VM (debug window, VBox)..."
    else
        TYPE="headless"
        echo "Starting VM (headless, VBox)..."
    fi
    echo "  Connect: ./vm-connect.sh"
    echo "  Stop:    ./vm-stop.sh"
    echo ""

    VBoxManage startvm "$VM_NAME" --type "$TYPE"
fi