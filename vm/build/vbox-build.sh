#!/bin/bash
# Build the VirtualBox VM image from scratch (instructor use).
#
# Full build:
#   ./vbox-build.sh
#     1. Download Ubuntu cloud image (qcow2)
#     2. Convert to VDI, resize
#     3. Build cloud-init seed ISO
#     4. Create VM
#     5. First boot: apply cloud-init
#     6. Second boot: install P4 tools over SSH
#     7. Export to .ova
#
# Partial build (stop after cloud-init, for manual install):
#   ./vbox-build.sh --noinstall
#     Runs steps 1-5 only. VM is left ready to boot for manual setup.
#     Skips steps 6-7.
#
# Output: vm/ans.ova

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VM_NAME="ans-build"
OVA_OUT="$VM_DIR/ans.ova"
VDI="$VM_DIR/ans.vdi"
CLOUD_IMAGE="$VM_DIR/ubuntu-22.04-cloudimg-amd64.img"
CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
CLOUD_CONFIG="$SCRIPT_DIR/vbox.yaml"
INSTALL_SCRIPT="$SCRIPT_DIR/install.sh"
LOGFILE="$SCRIPT_DIR/vbox-build.log"
# --- SYS config ---
DISK_SIZE_MB=51200   # 50 GB
RAM=16000
CPUS=8
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

command -v VBoxManage >/dev/null || { echo "ERROR: VBoxManage not found."; exit 1; }
command -v qemu-img  >/dev/null || { echo "ERROR: qemu-img not found (needed to convert cloud image)."; exit 1; }
[ ! -f "$CLOUD_CONFIG" ]   && echo "ERROR: $CLOUD_CONFIG not found." && exit 1
[ ! -f "$INSTALL_SCRIPT" ] && echo "ERROR: $INSTALL_SCRIPT not found." && exit 1

# --- Clean any stale VM from a previous build ---
if VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
    echo "Removing previous $VM_NAME..."
    VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
    sleep 2
    VBoxManage unregistervm "$VM_NAME" --delete
fi
[ -f "$OVA_OUT" ] && { read -p "$OVA_OUT exists. Delete? (y/N) " -r; [[ $REPLY =~ ^[Yy]$ ]] && rm "$OVA_OUT" || exit 1; }
[ -f "$VDI" ] && rm "$VDI"

# --- Download cloud image ---
if [ ! -f "$CLOUD_IMAGE" ]; then
    echo "[1] Downloading Ubuntu cloud image..."
    wget -O "$CLOUD_IMAGE" "$CLOUD_IMAGE_URL"
else
    echo "[1] Cloud image found."
fi

# --- Convert qcow2 → VDI, resize ---
echo "[2] Converting to VDI and resizing to ${DISK_SIZE_MB}MB..."
qemu-img convert -O vdi "$CLOUD_IMAGE" "$VDI"
VBoxManage modifyhd "$VDI" --resize $DISK_SIZE_MB

# --- Build cloud-init seed ISO ---
echo "[3] Building cloud-init seed..."
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
cp "$CLOUD_CONFIG" "$TMPDIR/user-data"
echo "instance-id: ans-vm" > "$TMPDIR/meta-data"

SEED_ISO="$VM_DIR/seed.iso"
if command -v genisoimage &>/dev/null; then
    genisoimage -quiet -output "$SEED_ISO" -volid cidata -joliet -rock \
        "$TMPDIR/user-data" "$TMPDIR/meta-data"
elif command -v mkisofs &>/dev/null; then
    mkisofs -quiet -output "$SEED_ISO" -volid cidata -joliet -rock \
        "$TMPDIR/user-data" "$TMPDIR/meta-data"
elif command -v hdiutil &>/dev/null; then
    hdiutil makehybrid -quiet -o "$SEED_ISO" -hfs -joliet -iso -default-volume-name cidata "$TMPDIR"
else
    echo "ERROR: no ISO tool (genisoimage/mkisofs/hdiutil)."; exit 1
fi

# --- Create VM ---
echo "[4] Creating VirtualBox VM..."
VBoxManage createvm --name "$VM_NAME" --ostype Ubuntu_64 --register
VBoxManage modifyvm "$VM_NAME" \
    --memory $RAM --cpus $CPUS \
    --nic1 nat --natpf1 "ssh,tcp,,${SSH_PORT},,22" \
    --graphicscontroller vmsvga --vram 16 \
    --boot1 disk --boot2 none --boot3 none --boot4 none

VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$VDI"
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium "$SEED_ISO"

# --- First boot: cloud-init (powers off automatically) ---
echo "[5] Applying cloud-init configuration..."
VBoxManage startvm "$VM_NAME" --type headless > "$LOGFILE" 2>&1

echo -n "    Waiting for shutdown"
for i in {1..120}; do
    if ! VBoxManage list runningvms | grep -q "\"$VM_NAME\""; then
        echo " done."; break
    fi
    printf "."; sleep 5
    [ $i -eq 120 ] && { echo " timeout."; exit 1; }
done

# Detach seed ISO so it doesn't boot again
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium emptydrive
rm -f "$SEED_ISO"

if [ $SKIP_INSTALL -eq 1 ]; then
    echo "Skipping install (--noinstall). VM is ready for manual software installation."
    echo "  Boot it:    VBoxManage startvm $VM_NAME --type headless"
    echo "  SSH in:     sshpass -p $SSH_PASS ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost"
    echo "  Or gui:     VBoxManage startvm $VM_NAME --type gui"
    exit 0
fi

# --- Second boot: install P4 tools over SSH ---
echo "[6] Installing P4 tools inside VM (this takes hours)..."
VBoxManage startvm "$VM_NAME" --type headless >> "$LOGFILE" 2>&1

# SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
echo -n "    Waiting for SSH"
for i in {1..60}; do
    # if ssh $SSH_OPTS -o ConnectTimeout=2 -p $SSH_PORT "$SSH_USER@localhost" true 2>/dev/null; then
    if $SSH -o ConnectTimeout=2 "$SSH_USER@localhost" true 2>/dev/null; then
        echo " ready."; break
    fi
    printf "."; sleep 5
    [ $i -eq 60 ] && { echo " timeout."; exit 1; }
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
sleep 5
while VBoxManage list runningvms | grep -q "\"$VM_NAME\""; do sleep 2; done

# [ $INSTALL_RC -ne 0 ] && { echo "ERROR: install.sh failed (exit $INSTALL_RC)."; tail -20 "$LOGFILE"; exit 1; }

# --- Export to OVA ---
# echo "[7] Exporting to $OVA_OUT..."
# # Remove SSH port-forward before export — students' start.sh adds it on import
# VBoxManage modifyvm "$VM_NAME" --natpf1 delete ssh 2>/dev/null || true
# VBoxManage export "$VM_NAME" --output "$OVA_OUT" --vsys 0 --product "Programmable Networks VM" --version "1.0"
# # --vsys 0 --product "ANS Course VM" --version "1.0"

# # --- Clean up build VM ---
# VBoxManage unregistervm "$VM_NAME" --delete

# echo ""
# echo "Done: $OVA_OUT"