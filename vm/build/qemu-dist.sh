#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
qemu-img convert -O qcow2 -c $VM_DIR/ans.qcow2 $VM_DIR/dist/ans.qcow2