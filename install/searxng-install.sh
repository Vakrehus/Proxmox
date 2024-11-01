#!/usr/bin/env bash
# Copyright (c) 2024 Vakrehus
# Author: Vakrehus

# Setup script environment
set -o errexit  # Exit if any command fails
set -o errtrace # Exit if error in any pipe
set -o nounset  # Exit if undefined variable
set -o pipefail # Exit if pipe fails

# Import build function
source <(curl -s https://raw.githubusercontent.com/Vakrehus/Proxmox/main/misc/build.func)

# Variables
SCRIPT_VERSION="1.0"
SCRIPT_AUTHOR="Vakrehus"
GITHUB_REPO="https://raw.githubusercontent.com/Vakrehus/Proxmox/main/install"

# Define some colors
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

# Repo URL for build script
SearXNG_SCRIPT="${GITHUB_REPO}/searxng-build.sh"

# Header
clear
cat <<"EOF"
    ____                 __  ___   ______
   / __/___  ____ ______\ \/ / | / / __ \
  / /_/ __ \/ __ `/ ___/\  /  |/ / / / /
 / __/ /_/ / /_/ / /    / / /|  / /_/ /
/_/  \____/\__,_/_/    /_/_/ |_/\____/

EOF

# Show script info
printf "${GREEN}%s${NC}\n" "SearXNG LXC Container Install Script"
printf "${GREEN}%s${NC}\n" "Script Version: $SCRIPT_VERSION"
printf "${GREEN}%s${NC}\n" "Author: $SCRIPT_AUTHOR"
printf "\n"

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

# Download and execute build script in container
msg "Downloading and executing build script..."

# Create temp script in container and execute it
pct exec "$CTID" -- bash -c "curl -s $SearXNG_SCRIPT -o /tmp/build.sh && chmod +x /tmp/build.sh && bash /tmp/build.sh"

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
