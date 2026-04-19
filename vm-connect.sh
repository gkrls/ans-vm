#!/bin/bash
#  SSH into the running VM with X11 forwarding.
#
#  Usage: ./vm-connect.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_PORT=2222
SSH_USER="ans"

case "$DISPLAY" in
    ""|needs-to-be-defined) export DISPLAY=localhost:0.0 ;;
esac

exec ssh -F /dev/null -Y \
    -o IgnoreUnknown=ObscureKeystrokeTiming \
    -o ObscureKeystrokeTiming=no \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -p "$SSH_PORT" \
    "$SSH_USER@localhost"

# SSH_BIN=ssh
# case "$(uname -s)" in
#     MINGW*|MSYS*|CYGWIN*)
#         if [ -x /C/Windows/System32/OpenSSH/ssh.exe ]; then
#             SSH_BIN=/C/Windows/System32/OpenSSH/ssh.exe
#         fi
#         ;;
# esac

# exec "$SSH_BIN" -F /dev/null -Y -v \
#     -o IgnoreUnknown=ObscureKeystrokeTiming \
#     -o ObscureKeystrokeTiming=no \
#     -o StrictHostKeyChecking=no \
#     -o UserKnownHostsFile=/dev/null \
#     -o LogLevel=ERROR \
#     -p "$SSH_PORT" \
#     "$SSH_USER@localhost"