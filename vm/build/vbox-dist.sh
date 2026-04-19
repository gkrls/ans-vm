#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_NAME="ans"

# Ensure VM is shut down
VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
sleep 2

# Strip build-time config (added back by student's vm-start.sh)
VBoxManage modifyvm "$VM_NAME" --natpf1 delete ssh 2>/dev/null || true
VBoxManage sharedfolder remove "$VM_NAME" --name hostshare 2>/dev/null || true

# Export
mkdir -p "$VM_DIR/dist"
VBoxManage export "$VM_NAME" --output "$VM_DIR/dist/ans.ova" --vsys 0 --product "Programmable Networks VM" --version "1.0"

echo "Done: $VM_DIR/dist/ans.ova"