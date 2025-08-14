#!/bin/sh

# Source the centralized configuration file
source ./config.sh

# Function to print a warning
warn() {
    echo "WARNING: $1"
}

# Function to print and exit on error
exit_on_error() {
    echo "$1"
    exit 1
}

# Check if connected to the internet
ping -c 1 google.com > /dev/null 2>&1
if [ $? -ne 0 ]; then
    exit_on_error "No internet connection. Please download the necessary packages manually."
else
    echo "Internet connection verified."
fi

# Ensure PATH includes Entware binaries
export PATH=$PATH:/opt/bin:/opt/sbin

# Ensure necessary system packages are installed
echo "Checking and installing required system packages and updates..."
/opt/bin/opkg update
/opt/bin/opkg install sudo bash

# Fix sudo permissions
echo "Fixing sudo permissions..."
chown root:root /opt/bin/sudo
chmod 4755 /opt/bin/sudo
if [ -f "/opt/lib/sudo/sudoers.so" ]; then
    chown root:root /opt/lib/sudo/sudoers.so
    chmod 644 /opt/lib/sudo/sudoers.so
fi

# Create sudo configuration
mkdir -p /opt/etc
cat > /opt/etc/sudoers << 'EOF'
# /etc/sudoers
#
# This file MUST be edited with the 'visudo' command as root.
#
# See the man page for details on how to write a sudoers file.
#

Defaults        env_reset

# Host alias specification

# User alias specification

# Cmnd alias specification

# User privilege specification
root    ALL=(ALL) ALL
moonrakeruser ALL=(ALL) NOPASSWD: ALL

# Allow members of group sudo to execute any command
%sudo   ALL=(ALL) ALL
EOF

# Set proper permissions for sudoers file
chown root:root /opt/etc/sudoers
chmod 440 /opt/etc/sudoers

# Detect existing Moonraker installation
EXISTING_MOONRAKER=$(ps aux | grep -v grep | grep moonraker | head -1 | awk '{print $11}')
if [ -n "$EXISTING_MOONRAKER" ]; then
    echo "Moonraker is already running at: $EXISTING_MOONRAKER"
    echo "Configuring Fluidd and Mainsail with the existing Moonraker service."

    # Make sure directories exist for UI files
    mkdir -p /usr/data/fluidd
    mkdir -p /usr/data/mainsail

    # Make sure scripts are executable
    if [ -f "$SCRIPTS_DIR/install_ui_only.sh" ]; then
        chmod +x "$SCRIPTS_DIR/install_ui_only.sh"
        chmod +x "$SCRIPTS_DIR/setup_nginx.sh"
        
        # Run the UI installer script first
        echo "Installing UI files..."
        $SCRIPTS_DIR/install_ui_only.sh || echo "UI installation had issues, continuing..."
        
        # Run the Nginx setup script directly
        $SCRIPTS_DIR/setup_nginx.sh || exit_on_error "Failed to configure Nginx"
    else
        # If script doesn't exist, try to get UI files directly with git
        echo "install_ui_only.sh not found. Installing UI files directly..."
        cd /usr/data
        rm -rf tmp
        mkdir -p tmp
        
        # Install Mainsail
        echo "Cloning Mainsail..."
        if git clone --depth=1 https://github.com/mainsail-crew/mainsail.git tmp/mainsail; then
            rm -rf /usr/data/mainsail/*
            cp -r tmp/mainsail/* /usr/data/mainsail/
            echo "✓ Mainsail installed"
        else
            echo "✗ Failed to install Mainsail"
        fi
        
        # Install Fluidd  
        echo "Cloning Fluidd..."
        if git clone --depth=1 https://github.com/fluidd-core/fluidd.git tmp/fluidd; then
            rm -rf /usr/data/fluidd/*
            cp -r tmp/fluidd/* /usr/data/fluidd/
            echo "✓ Fluidd installed"
        else
            echo "✗ Failed to install Fluidd"
        fi
        
        rm -rf tmp
        
        # Run the Nginx setup script
        if [ -f "$SCRIPTS_DIR/setup_nginx.sh" ]; then
            chmod +x "$SCRIPTS_DIR/setup_nginx.sh"
            $SCRIPTS_DIR/setup_nginx.sh || exit_on_error "Failed to configure Nginx"
        fi
    fi
    
    echo "Installation complete!"
    IP=$(ifconfig | grep -A1 eth0 | grep "inet addr" | cut -d: -f2 | awk '{print $1}')
    if [ -z "$IP" ]; then
        IP=$(ifconfig | grep -A1 wlan0 | grep "inet addr" | cut -d: -f2 | awk '{print $1}')
    fi
    if [ -z "$IP" ]; then
        IP=$(ip route get 1 | awk '{print $7;exit}' 2>/dev/null)
    fi
    if [ -z "$IP" ]; then
        IP="your_printer_ip"
    fi
    
    echo "You can access the interfaces at:"
    echo "- Mainsail: http://${IP}:4409"
    echo "- Fluidd: http://${IP}:4408"
    exit 0
fi

echo "Moonraker is not running. Proceeding with full installation."

# Ensure necessary directories exist
mkdir -p "$PACKAGES_DIR/python" "$PACKAGES_DIR/ipk" "$FLUIDD_KLIPPER_CFG_DIR" "$TMPDIR"

# Verify that the 'python' and 'ipk' directories exist under 'packages'
if [ ! -d "$PACKAGES_DIR/python" ]; then
    mkdir -p "$PACKAGES_DIR/python"
    echo "Created directory $PACKAGES_DIR/python"
fi

if [ ! -d "$PACKAGES_DIR/ipk" ]; then
    mkdir -p "$PACKAGES_DIR/ipk"
    echo "Created directory $PACKAGES_DIR/ipk"
fi

# Check for Python version compatibility
echo "Checking Python version..."
python_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
required_python_version="3.6"
if [ "$(printf '%s\n' "$required_python_version" "$python_version" | sort -V | head -n1)" != "$required_python_version" ]; then
    echo "Python version is less than $required_python_version. Upgrading Python..."
    /opt/bin/opkg install python3 || exit_on_error "Failed to upgrade Python"
else
    echo "Python version is $python_version, which is compatible."
fi

#pip error on 19 update to fix 
pip3 install --upgrade pip

# Function to check if a Python package is installed
is_python_package_installed() {
    pip3 show "$1" > /dev/null 2>&1
    return $?
}

# Function to check if an IPK package is installed
is_ipk_package_installed() {
    /opt/bin/opkg list-installed | grep -q "$1"
    return $?
}

# Install necessary .whl files
install_whl_files() {
    for file in "$@"; do
        package_name=$(echo "$file" | sed 's/-[0-9].*//')
        if [ ! -f "$PACKAGES_DIR/python/$file" ]; then
            if is_python_package_installed "$package_name"; then
                echo "$package_name is already installed."
            else
                warn "Required file $file not found in $PACKAGES_DIR/python and $package_name is not installed. Attempting to download and install..."
                pip3 install "$package_name" || exit_on_error "Failed to install $package_name from PyPI"
            fi
        else
            pip3 install "$PACKAGES_DIR/python/$file" || exit_on_error "Failed to install $file from local file"
        fi
    done
}

install_whl_files \
    "zipp-3.18.1-py3-none-any.whl" \
    "typing_extensions-4.11.0-py3-none-any.whl" \
    "tomli-2.0.1-py3-none-any.whl" \
    "setuptools_scm-8.1.0-py3-none-any.whl" \
    "importlib_metadata-7.1.0-py3-none-any.whl" \
    "Markdown-3.6-py3-none-any.whl" \
    "mkdocs-1.6.0-py3-none-any.whl" \
    "mergedeep-1.3.4-py3-none-any.whl" \
    "packaging-24.0-py3-none-any.whl" \
    "jinja2-3.1.4-py3-none-any.whl" \
    "watchdog-2.1.9-py3-none-manylinux2014_armv7l.whl" \
    "lmdb-1.4.1-cp38-cp38-manylinux2014_x86_64.whl"

# Ensure necessary system libraries are installed
install_system_libraries() {
    echo "Installing necessary system libraries..."
    /opt/bin/opkg update
    /opt/bin/opkg install libsodium libjpeg zlib || exit_on_error "Failed to install necessary system libraries"
}

install_system_libraries

# Install required dependencies from source or alternative methods
install_from_source_or_alternative() {
    echo "Attempting to install $1 from source or alternative method..."
    case "$1" in
        python3-virtualenv)
            pip3 install virtualenv || exit_on_error "Failed to install virtualenv"
            ;;
        python3-dev)
            echo "Skipping python3-dev as it's not installable via pip"
            ;;
        liblmdb-dev)
            pip3 install lmdb || exit_on_error "Failed to install lmdb"
            ;;
        libopenjp2-7)
            pip3 install pillow || exit_on_error "Failed to install pillow (includes support for openjp2)"
            ;;
        libsodium-dev)
            pip3 install libnacl || warn "Failed to install libnacl, this might impact functionality depending on its usage"
            ;;
        zlib1g-dev)
            python3 -c "import zlib" || exit_on_error "zlib not available in Python standard library"
            ;;
        libjpeg-dev)
            pip3 install pillow || exit_on_error "Failed to install pillow (includes support for libjpeg)"
            ;;
        packagekit)
            echo "Skipping packagekit as there's no direct equivalent"
            ;;
        wireless-tools)
            echo "Skipping wireless-tools as there's no direct equivalent"
            ;;
        curl)
            /opt/bin/opkg install curl || exit_on_error "Failed to install curl"
            ;;
        *)
            warn "No alternative installation method for $1"
            ;;
    esac
}

# List of required dependencies to install from source or alternative methods
required_dependencies="python3-virtualenv python3-dev liblmdb-dev libopenjp2-7 libsodium-dev zlib1g-dev libjpeg-dev packagekit wireless-tools curl"

# Install the required dependencies
for dep in $required_dependencies; do
    if ! is_python_package_installed "$dep" && ! is_ipk_package_installed "$dep"; then
        install_from_source_or_alternative "$dep"
    fi
done

# Backup existing printer.cfg
if [ -f "$PRINTER_CFG" ]; then
    echo "Backing up existing printer.cfg to $BACKUP_PRINTER_CFG"
    cp "$PRINTER_CFG" "$BACKUP_PRINTER_CFG" || exit_on_error "Failed to backup printer.cfg"
else
    echo "No existing printer.cfg found to backup."
fi

# Ensure printer.cfg is accessible
if [ ! -d "$FLUIDD_KLIPPER_CFG_DIR" ]; then
    echo "Creating directory $FLUIDD_KLIPPER_CFG_DIR"
    mkdir -p "$FLUIDD_KLIPPER_CFG_DIR" || exit_on_error "Failed to create directory $FLUIDD_KLIPPER_CFG_DIR"
fi

# Copy or create a symlink for the printer.cfg file
if [ -f "$PRINTER_CFG" ]; then
    echo "Copying printer.cfg to $FLUIDD_KLIPPER_CFG_DIR"
    cp "$PRINTER_CFG" "$FLUIDD_KLIPPER_CFG_DIR/printer.cfg" || exit_on_error "Failed to copy printer.cfg"
else
    exit_on_error "No printer.cfg found to copy."
fi

# Ensure scripts directory exists
if [ ! -d "$SCRIPTS_DIR" ]; then
    exit_on_error "Scripts directory not found at $SCRIPTS_DIR. Please check your repository structure."
fi

# Ensure scripts are executable
chmod +x "$SCRIPTS_DIR/install_moonraker.sh" || exit_on_error "Failed to make install_moonraker.sh executable"
chmod +x "$SCRIPTS_DIR/setup_nginx.sh" || exit_on_error "Failed to make setup_nginx.sh executable"

# Create moonrakeruser if it doesn't exist
if ! id "moonrakeruser" >/dev/null 2>&1; then
    echo "Creating user moonrakeruser..."
    #check if /home exists and if not make it
    if [ ! -d "$DIRECTORY" ]; then
      mkdir /home
    fi
    adduser -h /usr/data/home/moonrakeruser -D moonrakeruser || exit_on_error "Failed to create user moonrakeruser"
else
    echo "User moonrakeruser already exists."
fi

# Ensure moonrakeruser has ownership of the /usr/data directory
chown -R moonrakeruser:moonrakeruser /usr/data

# Run the install_moonraker.sh script directly (not as moonrakeruser)
echo "Running install_moonraker.sh..."
sh "$SCRIPTS_DIR/install_moonraker.sh" || exit_on_error "Failed to run install_moonraker.sh"

echo "Installation complete! Mainsail and Fluidd are installed."
echo "You can access Mainsail at http://your_printer_ip:4409 and Fluidd at http://your_printer_ip:4408"
