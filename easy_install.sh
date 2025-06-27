#!/bin/sh

# Easy installation script for Creality K1 and K1-Max Setup for Mainsail and Fluidd
# This script handles the entire installation process, including Entware

# Function to print and exit on error
exit_on_error() {
    echo "ERROR: $1"
    exit 1
}

# Function to print warning but continue
warn() {
    echo "WARNING: $1"
}

# Function to print step information
step() {
    echo ""
    echo "====================================================================="
    echo "STEP: $1"
    echo "====================================================================="
}

step "Checking internet connection"
ping -c 1 google.com > /dev/null 2>&1
if [ $? -ne 0 ]; then
    exit_on_error "No internet connection. Please ensure your printer is connected to the internet."
else
    echo "Internet connection verified."
fi

step "Checking if Entware is installed"
if [ ! -d "/opt" ] || [ ! -f "/opt/bin/opkg" ]; then
    echo "Entware is not installed. Installing Entware now..."
    
    # Navigate to /tmp directory
    cd /tmp || exit_on_error "Failed to navigate to /tmp directory"
    
    # Remove any existing generic.sh file
    rm -f generic.sh
    
    # Download the Entware installer
    echo "Downloading Entware installer..."
    wget --no-check-certificate http://bin.entware.net/mipselsf-k3.4/installer/generic.sh || exit_on_error "Failed to download Entware installer"
    
    # Run the Entware installer
    echo "Running Entware installer..."
    sh generic.sh || exit_on_error "Failed to install Entware"
    
    echo "Entware installed successfully."
else
    echo "Entware is already installed."
fi

# Add Entware to PATH
export PATH=$PATH:/opt/bin:/opt/sbin

step "Creating necessary directories"
mkdir -p /usr/data/creality-k1-setup/scripts || exit_on_error "Failed to create directories"
mkdir -p /usr/data/packages/python || exit_on_error "Failed to create python packages directory"
mkdir -p /usr/data/packages/ipk || exit_on_error "Failed to create ipk packages directory"

step "Downloading installation files"
cd /usr/data/creality-k1-setup || exit_on_error "Failed to navigate to setup directory"

# Download main files
echo "Downloading main installation files..."
wget --no-check-certificate -O install.sh https://raw.githubusercontent.com/Exieros/creality-k1-setup/main/install.sh || exit_on_error "Failed to download install.sh"
wget --no-check-certificate -O config.sh https://raw.githubusercontent.com/Exieros/creality-k1-setup/main/config.sh || exit_on_error "Failed to download config.sh"

# Download script files
echo "Downloading script files..."
cd /usr/data/creality-k1-setup/scripts || exit_on_error "Failed to navigate to scripts directory"
wget --no-check-certificate -O install_mnrk.sh https://raw.githubusercontent.com/Exieros/creality-k1-setup/main/scripts/install_mnrk.sh || exit_on_error "Failed to download install_moonraker.sh"
wget --no-check-certificate -O setup_nginx.sh https://raw.githubusercontent.com/Exieros/creality-k1-setup/main/scripts/setup_nginx.sh || exit_on_error "Failed to download setup_nginx.sh"
wget --no-check-certificate -O install_ui_only.sh https://raw.githubusercontent.com/Exieros/creality-k1-setup/main/scripts/install_ui_only.sh || exit_on_error "Failed to download install_ui_only.sh"
wget --no-check-certificate -O verify_packages.sh https://raw.githubusercontent.com/Exieros/creality-k1-setup/main/scripts/verify_packages.sh || exit_on_error "Failed to download verify_packages.sh"

step "Setting executable permissions"
chmod +x /usr/data/creality-k1-setup/install.sh || exit_on_error "Failed to set permissions on install.sh"
chmod +x /usr/data/creality-k1-setup/scripts/*.sh || exit_on_error "Failed to set permissions on script files"

step "Running installation script"
cd /usr/data/creality-k1-setup || exit_on_error "Failed to navigate to setup directory"
./install.sh || exit_on_error "Installation failed"

step "Installation complete!"
echo "Mainsail and Fluidd have been installed on your Creality K1/K1-Max."
echo "You can access them at:"
echo "- Mainsail: http://your_printer_ip:4409"
echo "- Fluidd: http://your_printer_ip:4408"
echo ""
echo "Thank you for using this installer."
