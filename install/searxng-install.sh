# Verify installation
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

# Display actual configuration values
display_config() {
    print_green "\nInstallation complete! Configuration summary:"
    
    # Read values from settings.yml using grep and awk
    local SECRET_KEY=$(grep 'secret_key' /etc/searxng/settings.yml | awk -F': ' '{print $2}' | tr -d '"')
    local BIND_ADDRESS=$(grep 'bind_address' /etc/searxng/settings.yml | awk -F': ' '{print $2}' | tr -d '"')
    local PORT=$(grep '  port' /etc/searxng/settings.yml | awk -F': ' '{print $2}')
    local REDIS_URL=$(grep 'url' /etc/searxng/settings.yml | grep 'redis' | awk -F': ' '{print $2}' | tr -d '"')
    local DEBUG_MODE=$(grep 'debug' /etc/searxng/settings.yml | head -1 | awk -F': ' '{print $2}')

    # Display the actual values
    print_red "Secret Key: ${SECRET_KEY}"
    print_red "Bind Address: ${BIND_ADDRESS}"
    print_red "Port: ${PORT}"
    print_red "Redis URL: ${REDIS_URL}"
    print_red "Debug Mode: ${DEBUG_MODE}"
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

    # Display actual configuration
    display_config
}

# Run main installation
main
