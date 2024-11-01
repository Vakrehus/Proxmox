#!/usr/bin/env bash
# Copyright (c) 2024 Vakrehus
# Author: Vakrehus

# Setup script environment
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

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

# Function to check if command executed successfully
check_command() {
    if [ $? -ne 0 ]; then
        print_red "Error: $1 failed"
        exit 1
    fi
}

# Function to install dependencies
install_dependencies() {
    print_green "Installing dependencies..."
    apt update && apt upgrade -y
    apt install -y redis-server git python3-pip python3-venv build-essential \
        python3-dev libffi-dev libssl-dev whiptail python3-yaml
    check_command "Package installation"
}

# Function to setup SearXNG user and directories
setup_user_dirs() {
    print_green "Setting up user and directories..."
    id -u searxng &>/dev/null || useradd -r -s /bin/false searxng
    mkdir -p /usr/local/searxng /etc/searxng
    chown searxng:searxng /usr/local/searxng /etc/searxng
    check_command "User and directory setup"
}

# Function to setup Python environment
setup_python_env() {
    print_green "Setting up Python environment..."
    sudo -u searxng python3 -m venv /usr/local/searxng/searx-pyenv
    source /usr/local/searxng/searx-pyenv/bin/activate
    pip install --upgrade pip setuptools wheel
    pip install pyyaml
    pip install -e /usr/local/searxng/searxng-src
    check_command "Python environment setup"
}

# Function to generate configuration
generate_config() {
    local SECRET_KEY=$(openssl rand -hex 32)
    local BIND_ADDRESS="0.0.0.0"
    local PORT="8888"
    local REDIS_URL="redis://127.0.0.1:6379/0"
    local DEBUG_MODE="false"

    print_green "Generating configuration..."
    cat <<EOL > /etc/searxng/settings.yml
# SearXNG settings
use_default_settings: true
general:
  debug: ${DEBUG_MODE}
  instance_name: "SearXNG"
  privacypolicy_url: false
  contact_url: false
server:
  bind_address: "${BIND_ADDRESS}"
  port: ${PORT}
  secret_key: "${SECRET_KEY}"
  limiter: true
  image_proxy: true
redis:
  url: "${REDIS_URL}"
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
    check_command "Configuration generation"
}

# Function to setup systemd service
setup_service() {
    print_green "Setting up systemd service..."
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

    systemctl daemon-reload
    systemctl enable --now redis-server
    sleep 2  # Give Redis time to start
    systemctl enable --now searxng
    check_command "Service setup"
}

# Function to verify installation
verify_installation() {
    print_green "Verifying installation..."
    
    # Check if Redis is running
    if ! systemctl is-active --quiet redis-server; then
        print_red "Redis is not running"
        exit 1
    fi

    # Check if SearXNG is running
    if ! systemctl is-active --quiet searxng; then
        print_red "SearXNG is not running"
        exit 1
    fi

    # Check if port is listening
    if ! netstat -tuln | grep -q ":8888 "; then
        print_red "Port 8888 is not listening"
        exit 1
    fi
}

# Main installation
main() {
    # Install dependencies
    install_dependencies

    # Setup user and directories
    setup_user_dirs

    # Clone repository
    print_green "Cloning SearXNG repository..."
    if [ -d "/usr/local/searxng/searxng-src" ]; then
        cd /usr/local/searxng/searxng-src
        sudo -u searxng git pull
    else
        sudo -u searxng git clone https://github.com/searxng/searxng.git /usr/local/searxng/searxng-src
    fi
    check_command "Repository clone"

    # Setup Python environment
    setup_python_env

    # Generate configuration
    generate_config

    # Setup service
    setup_service

    # Verify installation
    verify_installation

    # Display configuration
    print_green "\nInstallation complete! Configuration summary:"
    print_red "Secret Key: $(grep secret_key /etc/searxng/settings.yml | awk '{print $2}')"
    print_red "Bind Address: 0.0.0.0"
    print_red "Port: 8888"
    print_red "Redis URL: redis://127.0.0.1:6379/0"
    print_red "Debug Mode: false"
}

# Run main installation
main
