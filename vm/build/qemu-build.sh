#!/bin/bash
# Build the QEMU VM image from scratch (instructor use).
#   1. Download Ubuntu cloud image
#   2. Resize it
#   3. Boot once with cloud-init to apply config
#   4. Boot again headless, scp install.sh in, run it, shut down
#
# Output: vm/ans.qcow2

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

QCOW2_IMAGE="$VM_DIR/ans.qcow2"
CLOUD_IMAGE="$VM_DIR/ubuntu-22.04-cloudimg-amd64.img"
CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
CLOUD_CONFIG="$SCRIPT_DIR/qemu.yaml"
INSTALL_SCRIPT="$SCRIPT_DIR/install.sh"
LOGFILE="$SCRIPT_DIR/qemu-build.log"
# --- SYS config ---
DISK_SIZE="50G"
RAM="16384"
CPUS="6"
# --- SSH config ---
SSH_USER="ans"
SSH_PASS="ans"
SSH_PORT=2222
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH="sshpass -p $SSH_PASS ssh $SSH_OPTS -p $SSH_PORT"
SCP="sshpass -p $SSH_PASS scp $SSH_OPTS -P $SSH_PORT"

# --- Parse args ---
SKIP_INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --noinstall) SKIP_INSTALL=1 ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done



# OS="$(uname -s)"
# case "$OS" in
#     Linux)
#         [ -e /dev/kvm ] && ACCEL="-accel kvm -cpu host" || ACCEL="-accel tcg"
#         ;;
#     Darwin)
#         if [ "$(uname -m)" = "arm64" ]; then
#             echo "ERROR: Building is not supported on Apple Silicon."
#             echo "       Use the prebuilt image via ../../download.sh instead."
#             exit 1
#         fi
#         ACCEL="-accel hvf -cpu Haswell,check=off"
#         ;;
#     *) echo "Unsupported OS: $OS"; exit 1 ;;
# esac

case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)
        [ -e /dev/kvm ] && ACCEL="-accel kvm -cpu host" || ACCEL="-accel tcg"
        ;;
    Darwin-x86_64)
        ACCEL="-accel hvf -cpu Haswell,check=off"
        ;;
    *)
        echo "ERROR: Building is only supported on Linux x86_64 or Intel Mac."
        echo "       Detected: $(uname -s)-$(uname -m)"
        exit 1
        ;;
esac

[ ! -f "$CLOUD_CONFIG" ]   && echo "ERROR: $CLOUD_CONFIG not found." && exit 1
[ ! -f "$INSTALL_SCRIPT" ] && echo "ERROR: $INSTALL_SCRIPT not found." && exit 1

if [ -f "$QCOW2_IMAGE" ]; then
    echo "$QCOW2_IMAGE already exists."
    read -p "Delete and create a new one? (y/N) " -r
    [[ ! $REPLY =~ ^[Yy]$ ]] && echo "Aborted." && exit 1
    rm "$QCOW2_IMAGE"
fi

if [ ! -f "$CLOUD_IMAGE" ]; then
    echo "[1] Downloading Ubuntu cloud image..."
    wget -O "$CLOUD_IMAGE" "$CLOUD_IMAGE_URL"
else
    echo "[1] Cloud image found."
fi

echo "[2] Creating VM disk ($DISK_SIZE)..."
cp "$CLOUD_IMAGE" "$QCOW2_IMAGE"
qemu-img resize "$QCOW2_IMAGE" "$DISK_SIZE"

echo "[3] Building cloud-init seed..."
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
cp "$CLOUD_CONFIG" "$TMPDIR/user-data"
echo "instance-id: ans-vm" > "$TMPDIR/meta-data"

SEED_ISO="$TMPDIR/seed.iso"
if command -v genisoimage &>/dev/null; then
    genisoimage -quiet -output "$SEED_ISO" -volid cidata -joliet -rock \
        "$TMPDIR/user-data" "$TMPDIR/meta-data"
elif command -v mkisofs &>/dev/null; then
    mkisofs -quiet -output "$SEED_ISO" -volid cidata -joliet -rock \
        "$TMPDIR/user-data" "$TMPDIR/meta-data"
else
    echo "ERROR: mkisofs/genisoimage not found." && exit 1
fi

echo "[4] Applying cloud-init configuration..."
qemu-system-x86_64 $ACCEL -m "$RAM" -smp "$CPUS" \
    -drive file="$QCOW2_IMAGE",if=virtio,format=qcow2 \
    -cdrom "$SEED_ISO" -nic user -nographic -no-reboot \
    > "$LOGFILE" 2>&1 &
QEMU_PID=$!
trap "kill $QEMU_PID 2>/dev/null; rm -rf $TMPDIR; exit 1" INT TERM

while kill -0 $QEMU_PID 2>/dev/null; do printf "."; sleep 5; done
echo ""
wait $QEMU_PID || { echo "ERROR: cloud-init failed."; tail -20 "$LOGFILE"; exit 1; }

# --- Stop here if --noinstall ---
if [ $SKIP_INSTALL -eq 1 ]; then
    echo "Skipping install (--noinstall). VM disk is ready at $QCOW2_IMAGE."
    echo "  Boot it manually:"
    echo "    qemu-system-x86_64 $ACCEL -m $RAM -smp $CPUS \\"
    echo "      -drive file=$QCOW2_IMAGE,if=virtio,format=qcow2 \\"
    echo "      -nic user,hostfwd=tcp::${SSH_PORT}-:22 -nographic"
    echo "  Then SSH in:"
    echo "    sshpass -p $SSH_PASS ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost"
    exit 0
fi

echo "[5] Installing P4 tools inside VM (can take hours)..."
qemu-system-x86_64 $ACCEL -m "$RAM" -smp "$CPUS" \
    -drive file="$QCOW2_IMAGE",if=virtio,format=qcow2 \
    -nic user,hostfwd=tcp::${SSH_PORT}-:22 \
    -nographic \
    >> "$LOGFILE" 2>&1 &
QEMU_PID=$!
trap "kill $QEMU_PID 2>/dev/null; rm -rf $TMPDIR; exit 1" INT TERM

# SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
echo -n "    Waiting for SSH"
for i in {1..60}; do
    # if ssh $SSH_OPTS -o ConnectTimeout=2 -p $SSH_PORT "$SSH_USER@localhost" true 2>/dev/null; then
    if $SSH -o ConnectTimeout=2 "$SSH_USER@localhost" true 2>/dev/null; then
        echo " ready."; break
    fi
    printf "."; sleep 5
    [ $i -eq 60 ] && { echo " timeout."; kill $QEMU_PID; exit 1; }
done

echo "    Copying install.sh..."
# scp $SSH_OPTS -P $SSH_PORT "$INSTALL_SCRIPT" "$SSH_USER@localhost:~/install.sh"
$SCP "$INSTALL_SCRIPT" "$SSH_USER@localhost:~/install.sh"

echo "    Running install.sh..."
# ssh $SSH_OPTS -p $SSH_PORT "$SSH_USER@localhost" "yes y | bash ~/install.sh" | tee -a "$LOGFILE"
$SSH "$SSH_USER@localhost" "yes y | bash ~/install.sh" | tee -a "$LOGFILE"
INSTALL_RC=${PIPESTATUS[0]}

if [ $INSTALL_RC -ne 0 ]; then
    echo ""
    echo "ERROR: install.sh failed (exit $INSTALL_RC)."
    echo "VM is still running — SSH in to inspect:"
    echo "    sshpass -p ans ssh -p $SSH_PORT ans@localhost"
    echo "When done, shut it down with: sudo poweroff"
    tail -20 "$LOGFILE"
    exit 1
fi

# Only shutdown and export once the VM is done

echo "    Shutting down VM..."
# ssh $SSH_OPTS -p $SSH_PORT "$SSH_USER@localhost" "sudo poweroff" || true
$SSH "$SSH_USER@localhost" "sudo poweroff" || true
wait $QEMU_PID 2>/dev/null || true

sed -i.bak 's/\x1b\[[0-9;]*m//g' "$LOGFILE" && rm -f "${LOGFILE}.bak"

if [ $INSTALL_RC -eq 0 ]; then
    echo ""; echo "Done: $QCOW2_IMAGE"
else
    echo ""; echo "ERROR: install.sh failed (exit $INSTALL_RC). Last 20 lines:"
    tail -20 "$LOGFILE"; exit 1
fi