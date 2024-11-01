#!/usr/bin/env bash
# Copyright (c) 2024 Vakrehus
# Author: Vakrehus

# Setup script environment
set -o errexit  # Exit if any command fails
set -o errtrace # Exit if error in any pipe
set -o nounset  # Exit if undefined variable
set -o pipefail # Exit if pipe fails

# Define some colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YW='\033[33m'
NC='\033[0m'

# Function to print messages in green
print_green() {
    echo -e "${GREEN}$1${NC}"
}

# Function to print messages in red
print_red() {
    echo -e "${RED}$1${NC}"
}

# Function to print messages
msg() {
    echo -e "${GREEN}$1${NC}"
}

# Function to display header info
header_info() {
    clear
    cat <<"EOF"
    ____                 __  ___   ______
   / __/___  ____ ______\ \/ / | / / __ \
  / /_/ __ \/ __ `/ ___/\  /  |/ / / / /
 / __/ /_/ / /_/ / /    / / /|  / /_/ /
/_/  \____/\__,_/_/    /_/_/ |_/\____/

EOF
    
    echo -e "${GREEN}SearXNG LXC Container Install Script${NC}"
    echo -e "${GREEN}Script Version: ${YW}1.0${NC}"
    echo -e "${GREEN}Author: ${YW}Vakrehus${NC}"
    echo ""
}

# Basic LXC functions
create_lxc() {
    msg "Creating LXC container..."
    pct create "$CTID" "local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst" \
        -arch amd64 -cores "$CTCORES" -hostname "$CTHOSTNAME" -memory "$CTMEMORY" \
        -features nesting=1 -onboot 1 -swap "$CTSWAP" \
        -storage local-lvm -net0 name=eth0,bridge=vmbr0,ip=dhcp
}

start_lxc() {
    msg "Starting LXC container..."
    pct start "$CTID"
    sleep 3
}

basic_setup() {
    msg "Running basic setup..."
    pct exec "$CTID" -- bash -c "apt-get update && apt-get -y upgrade"
}

# Variables
SCRIPT_VERSION="1.0"
SCRIPT_AUTHOR="Vakrehus"

# Define container values
CTNAME="searxng"
CTID=$(pvesh get /cluster/nextid)
CTOSTYPE="debian"
CTOSVERSION="bookworm"
CTHOSTNAME="searxng-server"
CTSIZE="8G"
CTCORES="2"
CTMEMORY="2048"
CTSWAP="512"
CTNETWORK="eth0"
CTBRIDGE="vmbr0"
CTIP=""

# Display script info
header_info

print_green "Creating LXC container for SearXNG..."

# Create container
create_lxc

# Start container
start_lxc

# Setup OS
basic_setup

# Get container IP
CTIP=$(pct exec "$CTID" ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Create the build script directly in the container
msg "Creating and executing build script..."
cat > /tmp/build.sh <<'EOBUILD'
#!/bin/bash

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Function to print messages in green
print_green() {
    echo -e "${GREEN}$1${NC}"
}

# Function to print messages in red
print_red() {
    echo -e "${RED}$1${NC}"
}

# Main installation
echo "Starting SearXNG installation..."

# Update and install packages
apt update
apt upgrade -y
apt install -y redis-server git python3-pip python3-venv build-essential \
    python3-dev libffi-dev libssl-dev whiptail python3-yaml

# Create user and directories
useradd -r -s /bin/false searxng
mkdir -p /usr/local/searxng /etc/searxng
chown searxng:searxng /usr/local/searxng /etc/searxng

# Clone repository
if [ -d "/usr/local/searxng/searxng-src" ]; then
    cd /usr/local/searxng/searxng-src
    sudo -u searxng git pull
else
    sudo -u searxng git clone https://github.com/searxng/searxng.git /usr/local/searxng/searxng-src
fi

# Setup Python environment
sudo -u searxng python3 -m venv /usr/local/searxng/searx-pyenv
source /usr/local/searxng/searx-pyenv/bin/activate
pip install --upgrade pip setuptools wheel
pip install pyyaml
pip install -e /usr/local/searxng/searxng-src

# Generate configuration
SECRET_KEY=$(openssl rand -hex 32)

cat <<EOL > /etc/searxng/settings.yml
# SearXNG settings
use_default_settings: true
general:
  debug: false
  instance_name: "SearXNG"
  privacypolicy_url: false
  contact_url: false
server:
  bind_address: "0.0.0.0"
  port: 8888
  secret_key: "${SECRET_KEY}"
  limiter: true
  image_proxy: true
redis:
  url: "redis://127.0.0.1:6379/0"
ui:
  static_use_hash: true
enabled_plugins:
  - 'Hash plugin'
  - 'Self Information'
  - 'Tracker URL remover'
  - 'Ahmia blacklist'
search:
  safe_search: 2
  autocomplete: 'google'
engines:
  - name: google
    engine: google
    shortcut: gg
  - name: duckduckgo
    engine: duckduckgo
    shortcut: ddg
  - name: wikipedia
    engine: wikipedia
    shortcut: wp
  - name: github
    engine: github
    shortcut: gh
EOL

chown searxng:searxng /etc/searxng/settings.yml
chmod 640 /etc/searxng/settings.yml

# Create service file
cat <<EOL > /etc/systemd/system/searxng.service
[Unit]
Description=SearXNG service
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
User=searxng
Group=searxng
Environment="SEARXNG_SETTINGS_PATH=/etc/searxng/settings.yml"
ExecStart=/usr/local/searxng/searx-pyenv/bin/python -m searx.webapp
WorkingDirectory=/usr/local/searxng/searxng-src
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Start services
systemctl daemon-reload
systemctl enable --now redis-server
sleep 2
systemctl enable --now searxng

# Display configuration
echo -e "\nInstallation complete! Configuration summary:"
echo -e "${RED}Secret Key: $SECRET_KEY${NC}"
echo -e "${RED}Bind Address: 0.0.0.0${NC}"
echo -e "${RED}Port: 8888${NC}"
echo -e "${RED}Redis URL: redis://127.0.0.1:6379/0${NC}"
echo -e "${RED}Debug Mode: false${NC}"
EOBUILD

# Execute the build script in the container
pct exec "$CTID" -- bash -c "cat > /root/build.sh < /tmp/build.sh && chmod +x /root/build.sh && bash /root/build.sh"

# Summary and instructions
msg "SearXNG LXC container has been created!"
print_red "Container ID: $CTID"
print_red "Container IP: $CTIP"
print_red "Container Name: $CTNAME"
print_red "Container Hostname: $CTHOSTNAME"
print_red "Container Size: $CTSIZE"
print_red "Container Memory: $CTMEMORY"
print_red "Container Swap: $CTSWAP"
print_red "Container Cores: $CTCORES"
print_green "\nYou can now access SearXNG at http://${CTIP}:8888"
print_green "Installation is complete! You can connect to the container with:"
print_green "pct enter $CTID"

# Done
echo -e "\n${GREEN}Done!${NC}\n"
exit 0
