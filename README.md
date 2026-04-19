# ANS VM

A preconfigured Ubuntu 22.04 VM with P4 development tools for the ANS course.

## Quick Start

```bash
git clone <REPO> share/labs      # clone the lab repo into share/
./vm-download.sh                 # one-time: grab the prebuilt VM image ()
./vm-start.sh                    # boot the VM
./vm-connect.sh                     # SSH in (password: ans)
./vm-stop.sh                        # shut down (VBox only; QEMU: Ctrl+C in the start.sh window)
```
---

## Dependencies

Install these **before** running `./vm-start.sh`. Default backend per platform:

| Platform              | Backend          | Notes     |
|-----------------------|------------------|-----------|
| Linux                 | VirtualBox/QEMU  | **Default**: VirtualBox, <br/> **Override**: `./vm-start.sh --qemu` |
| Mac-Intel             | VirtualBox/QEMU  | **Default**: VirtualBox, <br/> **Override**: `./vm-start.sh --qemu` |
| Mac-Arm               | QEMU             | No overrides, Potentially very slow |
| Windows               | VirtualBox       | No overrides                        |

You can override with `./vm-start.sh --qemu` or `./start.sh --vbox` (for Linux and Mac-Intel only)
### Linux

1. **VirtualBox** — `sudo apt install virtualbox` (or your distro equivalent)
2. **OpenSSH client** — usually preinstalled; otherwise `sudo apt install openssh-client`
3. **X server** — any desktop Linux already has one.

### Mac-Intel

1. **VirtualBox** — https://www.virtualbox.org/wiki/Downloads
2. **XQuartz** (for X11 forwarding) — https://www.xquartz.org/

### Mac-Arm

1. **QEMU** — `brew install qemu`
2. **XQuartz** — https://www.xquartz.org/

> Note: x86 emulation on ARM is slow. If the VM is unusable on your machine, you may need to find an x86_64 Linux/Windows/Intel-Mac machine (lab, desktop, cloud VM).

### Windows

1. **VirtualBox** — https://www.virtualbox.org/wiki/Downloads
2. **Git for Windows** (includes Git Bash + OpenSSH) — https://git-scm.com/download/win
3. **VcXsrv** (for X11 forwarding) — https://sourceforge.net/projects/vcxsrv/
   - Launch "XLaunch" before connecting, pick "Multiple windows", **check "Disable access control"**.

Run all `./*.sh` scripts from **Git Bash**, not PowerShell or cmd.

### Optional: QEMU on Linux/Mac-Intel

If you prefer QEMU over VBox (`./start.sh --qemu`):

- **Linux:** `sudo apt install qemu-system-x86 qemu-utils`
- **Intel Mac:** `brew install qemu`

---

## X11 Forwarding

After connecting, GUI apps inside the VM (`xterm`, Wireshark, mininet's `xterm`) open as windows on your host. This requires:

- **Windows:** VcXsrv running, connect with `./connect.sh` (uses `ssh -Y`)
- **Mac:** XQuartz running, connect with `./connect.sh`
- **Linux:** nothing extra

---

## Troubleshooting

**`./start.sh`: command not found (Windows)** — you're in PowerShell. Open Git Bash.

**`./vm-start.sh`: VBoxManage: command not found (Windows)** — Add `C:\Program Files\Oracle\VirtualBox` to your system `PATH` via Settings → System → About → Advanced system settings → Environment Variables → Edit → New

**SSH connection refused** — VM is still booting. Wait ~30s and retry `./connect.sh`.

**X11: "Can't open display"** — Windows: VcXsrv isn't running, or "Disable access control" wasn't checked. Mac: XQuartz isn't running (`open -a XQuartz`).

**VBox shared folder empty inside VM** — the `vboxsf` group membership applies on next login; log out and back in, or reboot the VM.

**VBox: "VT-x is not available"** — enable virtualization in BIOS/UEFI. On Windows, also disable Hyper-V: `bcdedit /set hypervisorlaunchtype off` (admin PowerShell), then reboot.

---

## Building a VM from scratch

### Additional dependencies for building

On top of the student dependencies above, the build host needs:

#### Linux (recommended build host)

```bash
sudo apt install wget genisoimage qemu-utils virtualbox sshpass
sudo apt install qemu-system-x86      # only if building the QEMU image
```

- `qemu-utils` — provides `qemu-img`, required by **both** builds to convert the Ubuntu cloud image
- `genisoimage` — builds the cloud-init seed ISO
- `virtualbox` — only if building the VBox image
- `qemu-system-x86` — only if building the QEMU image

#### Intel Mac

```bash
brew install qemu wget hudochenkov/sshpass/sshpass cdrtools
```

For VBox builds, install VirtualBox from the website.

#### Windows / Apple Silicon Mac -- NOT SUPPORTED

### Building

```bash
cd vm/build
./qemu-build.sh    # builds vm/ans.qcow2
./vbox-build.sh    # builds vm/ans.ova
```

Each build downloads the Ubuntu cloud image, applies `cloud-init` config (qemu.yaml / vbox.yaml), boots the VM, copies `install.sh` in, runs it (up to hours) for P4Studio + P4Utils, and exports the final image to `vm/dist`.

Host the resulting image somewhere students can download (GitHub Releases, S3, university file share) and update `download.sh` to point at the URL.

---