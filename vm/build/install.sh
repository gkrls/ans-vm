#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo ""
echo "WARNING: This script installs ALL P4 development tools."
echo "It takes hours and should only be run ONCE on a fresh VM."
echo "Do NOT run this on an already configured VM."
echo ""
read -p "Continue? (y/N) " -r
[[ ! $REPLY =~ ^[Yy]$ ]] && echo "Aborted." && exit 0


cd ~

# Prevent kernel upgrades during install (apt upgrade would otherwise
# install a new kernel, which can corrupt the VM if install fails mid-way)
sudo apt-mark hold linux-image-generic linux-headers-generic linux-image-$(uname -r) linux-headers-$(uname -r)

# ------ TOFINO SDE (Open-P4Studio) ------
echo "[1] Installing Tofino SDE (Open-P4Studio)"

if [ ! -d ~/open-p4studio ]; then
    git clone https://github.com/p4lang/open-p4studio.git ~/open-p4studio
fi

cd ~/open-p4studio
git submodule update --init --recursive

cat > /tmp/sde.profile << 'EOF'
global-options: { build_model: true }
features:
  drivers:
    bfrt: true
    bfrt-generic-flags: true
    grpc: true
    thrift-driver: true
  p4-examples:
    - p4-16-programs
  switch:
    profile: x2_tofino
    sai: true
    thrift-switch: true
architectures:
  - tofino
  - tofino2
EOF

./p4studio/p4studio profile apply /tmp/sde.profile

sleep 1

# --- Add SDE, SDE_INSTALL etc to .bashrc
# --- But remove $SDE_INSTALL/bin from $PATH as its causing problems
#        1. protoc used py p4studio is different from the bmv2/p4utils one
if ! grep -q "SDE=" ~/.bashrc; then
    ./create-setup-script.sh | sed 's|^export PATH=|#export PATH=|' >> ~/.bashrc
fi
source <(./create-setup-script.sh | sed 's|^export PATH=|#export PATH=|')

# if ! grep -q "SDE=" ~/.bashrc; then
#     ./create-setup-script.sh >> ~/.bashrc
# fi

# source <(./create-setup-script.sh)

sudo ln -sf "$SDE_INSTALL/bin/p4c" /usr/local/bin/bf-p4c
# sudo ln -s $SDE_INSTALL/bin/p4c /usr/local/bin/bf-p4c

echo "[1] Tofino SDE installed "

sleep 1

# ------ P4Utils ------
echo "[2] Installing P4Utils"

wget -O install-p4-dev.sh https://raw.githubusercontent.com/nsg-ethz/p4-utils/master/install-tools/install-p4-dev.sh

sed -i 's|/home/ubuntu20/p4-tools/p4-utils#|#|g' install-p4-dev.sh
# sed -i 's|sudo apt-get -y .* upgrade|true|' install-p4-dev.sh # fix kernel upgrade
sed -i 's/libgc1c2/libgc1/g' install-p4-dev.sh  # fix libgc1c2 package

# export NEEDRESTART_MODE=a
# export DEBIAN_FRONTEND=noninteractive

bash install-p4-dev.sh

sleep 1

# By default the timeout is 10s which might be too small. Lets bump it to 60
sed -i 's/SWITCH_START_TIMEOUT = 10/SWITCH_START_TIMEOUT = 60/' ~/p4-tools/p4-utils/p4utils/mininetlib/node.py

sudo pip3 install psutil==5.9.4 #--break-system-packages

echo "[2] P4Utils installed"

echo "[3] Installing extra Python packages"

sudo pip3 install git+https://github.com/faucetsdn/ryu.git
sudo pip3 install eventlet==0.33.3 'dnspython>=2.0'

# Loosen Ryu's outdated eventlet pin so `pip check` stays clean
sudo sed -i 's/eventlet==0.31.1/eventlet>=0.33.3/' \
    /usr/local/lib/python3.10/dist-packages/ryu-4.34.dist-info/METADATA

sudo pip3 install \
    numpy \
    scipy \
    pandas \
    matplotlib \
    scapy \
    networkx \
    tqdm \
    requests \
    pyyaml

echo "[3] Extra Python packages installed"

sync