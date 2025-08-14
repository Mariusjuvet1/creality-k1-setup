#!/bin/sh

# Automated Moonraker/Nginx Installation Script for Creality K1
# Compatible with BusyBox sh shell - FULLY AUTOMATED

# Exit on errors
set -e

# Directories
USR_DATA="/usr/data"
MOONRAKER_DIR="${USR_DATA}/moonraker"
VENV_DIR="${USR_DATA}/moonraker-env"
CONFIG_DIR="${USR_DATA}/printer_data/config"
LOGS_DIR="${USR_DATA}/printer_data/logs"
FLUIDD_DIR="${USR_DATA}/fluidd"
MAINSAIL_DIR="${USR_DATA}/mainsail"
TMPDIR="${USR_DATA}/tmp"
SCRIPT_LOG="${USR_DATA}/moonraker_install.log"

# Create log file
echo "Starting installation script at $(date)" > "${SCRIPT_LOG}"
echo "--------------------------------------------------------------------------" >> "${SCRIPT_LOG}"

# Function to log and print
log() {
    echo "$@" | tee -a "${SCRIPT_LOG}"
}

# Create directories
mkdir -p "${TMPDIR}"
mkdir -p "${CONFIG_DIR}"
mkdir -p "${LOGS_DIR}"
mkdir -p "${FLUIDD_DIR}"
mkdir -p "${MAINSAIL_DIR}"

# Set TMPDIR for pip installations
export TMPDIR="${TMPDIR}"

# Path to Entware
export PATH=$PATH:/opt/bin:/opt/sbin

# Print status message
print_status() {
    log "==========================================================================="
    log "$(date +%H:%M:%S) - $1"
    log "==========================================================================="
}

# Exit on error
exit_on_error() {
    log "ERROR: $1"
    log "Check log at ${SCRIPT_LOG} for details"
    exit 1
}

# Force kill all processes - AGGRESSIVE CLEANUP
force_cleanup() {
    print_status "Performing aggressive cleanup of existing services"
    
    # Kill all Moonraker processes - find them by various methods
    log "Terminating all Moonraker instances..."
    
    # Method 1: Kill by name pattern but exclude .sh so this script doesn't die 
    ps | grep -v "grep\|install_moonraker.sh" | grep -E 'moonraker|python.*moonraker' | while read line; do
        pid=$(echo $line | awk '{print $1}')
        log "Found process PID $pid, terminating..."
        kill -9 $pid 2>/dev/null || true
    done
    
    # Method 2: Kill all python processes that might be running moonraker but don't kill grep or running .sh files
    ps | grep -v "grep\|install_moonraker.sh" | grep python | grep -v "$0" | while read line; do
        pid=$(echo $line | awk '{print $1}')
        cmdline=$(cat /proc/$pid/cmdline 2>/dev/null || echo "")
        if echo "$cmdline" | grep -q moonraker; then
            log "Found python moonraker PID $pid, terminating..."
            kill -9 $pid 2>/dev/null || true
        fi
    done
    
    # Kill all Nginx processes
    log "Terminating all Nginx instances..."
    ps | grep -v grep | grep nginx | while read line; do
        pid=$(echo $line | awk '{print $1}')
        log "Found nginx PID $pid, terminating..."
        kill -9 $pid 2>/dev/null || true
    done
    
    # Wait for processes to die
    sleep 2
    
    # Clean up remaining PIDs using killall as backup
    killall -9 moonraker 2>/dev/null || true
    killall -9 nginx 2>/dev/null || true
    
    # Clean up temporary files
    log "Removing temporary files"
    rm -rf "${TMPDIR:?}"/* 2>/dev/null || true
    rm -rf /root/.cache/pip 2>/dev/null || true
    mkdir -p "${TMPDIR}"
    
    # Clean up any stale PID files
    rm -f /var/run/moonraker.pid 2>/dev/null || true
    rm -f /var/run/nginx.pid 2>/dev/null || true
    
    # Give processes time to fully terminate
    sleep 3
    
    log "Cleanup completed"
}

# Install Moonraker
install_moonraker() {
    print_status "Installing Moonraker"
    
    # Check if Moonraker directory exists and remove if necessary
    if [ -d "${MOONRAKER_DIR}" ]; then
        log "Moonraker directory already exists. Deleting..."
        rm -rf "${MOONRAKER_DIR}" || exit_on_error "Failed to delete ${MOONRAKER_DIR}"
    fi
    
    # Create directory and clone repository
    log "Creating Moonraker directory and cloning repository"
    mkdir -p "${MOONRAKER_DIR}" || exit_on_error "Failed to create ${MOONRAKER_DIR}"
    cd "${USR_DATA}" || exit_on_error "Failed to change directory to ${USR_DATA}"
    
    # Clone with --depth=1 to minimize disk usage
    log "Cloning Moonraker repository"
    git clone --depth=1 https://github.com/Arksine/moonraker.git "${MOONRAKER_DIR}" || exit_on_error "Failed to clone Moonraker"
    
    log "Moonraker installed successfully"
    
    # Fix dbus_manager.py to avoid dependency issues
    print_status "Fixing dbus_manager.py to avoid dependency issues"
    cat > "${MOONRAKER_DIR}/moonraker/components/dbus_manager.py" << 'EOF'
# Modified dbus_manager.py for Creality K1
class DbusManager:
    def __init__(self, config):
        self.server = config.get_server()
        self.server.add_log_rollover_item("dbus_manager", None)

def load_component(config):
    return DbusManager(config)
EOF

    log "dbus_manager.py fixed successfully"
}

# Set up Python virtual environment
setup_venv() {
    print_status "Setting up Python virtual environment"
    
    # Remove existing virtual environment if it exists
    if [ -d "${VENV_DIR}" ]; then
        log "Removing existing virtual environment..."
        rm -rf "${VENV_DIR}"
    fi
    
    # Create virtual environment using system packages to save space
    log "Creating virtual environment with system packages..."
    python3 -m venv --system-site-packages "${VENV_DIR}" || {
        log "Failed to create virtual environment with venv module. Creating minimal environment..."
        
        # Create directory structure
        mkdir -p "${VENV_DIR}/bin"
        mkdir -p "${VENV_DIR}/lib/python3.8/site-packages"
        
        # Copy activate script
        cat > "${VENV_DIR}/bin/activate" << 'EOF'
# This file must be used with "source bin/activate" *from bash*
# You cannot run it directly
deactivate () {
    unset -f pydoc >/dev/null 2>&1
    unset -f deactivate
    unset VIRTUAL_ENV
    if [ ! "${1:-}" = "nondestructive" ] ; then
    # Self destruct!
        unset -f deactivate
    fi
}
VIRTUAL_ENV="$VENV_DIR"
export VIRTUAL_ENV
_OLD_VIRTUAL_PATH="$PATH"
PATH="$VIRTUAL_ENV/bin:$PATH"
export PATH
EOF
        
        # Create symlinks to system Python
        ln -sf $(which python3) "${VENV_DIR}/bin/python"
        ln -sf $(which python3) "${VENV_DIR}/bin/python3"
        ln -sf $(which pip3) "${VENV_DIR}/bin/pip"
        ln -sf $(which pip3) "${VENV_DIR}/bin/pip3"
    }
    
    # Install minimal dependencies
    log "Installing minimal Python dependencies..."
    pip3 install tornado==6.1 pyserial pillow --no-cache-dir || log "Warning: Some dependencies failed to install, but we'll continue anyway"
    
    log "Python virtual environment set up successfully"
}

# Create Moonraker configuration
create_moonraker_config() {
    print_status "Creating Moonraker configuration"
    
    log "Writing moonraker.conf to ${CONFIG_DIR}/moonraker.conf"
    cat > "${CONFIG_DIR}/moonraker.conf" << 'EOF'
[server]
host: 0.0.0.0
port: 7125
klippy_uds_address: /tmp/klippy_uds
# Disable dbus_manager to avoid dependency issues
disabled_components: ["dbus_manager"]
max_upload_size: 1024

[file_manager]
queue_gcode_uploads: False
enable_object_processing: False
enable_inotify_warnings: True

[database]
#enable_database_debug: False

[data_store]
temperature_store_size: 600
gcode_store_size: 1000

[machine]
provider: none
validate_service: False
validate_config: False

[authorization]
force_logins: False
cors_domains:
  *.local
  *.lan
  *://app.fluidd.xyz

trusted_clients:
  10.0.0.0/8
  127.0.0.0/8
  169.254.0.0/16
  172.16.0.0/12
  192.168.0.0/16
  FE80::/10
  ::1/128

# enables partial support of Octoprint API
[octoprint_compat]

# enables moonraker to track and store print history.
[history]

[update_manager]
channel: dev
refresh_interval: 168

[update_manager mainsail]
type: web
channel: stable
repo: mainsail-crew/mainsail
path: /usr/data/mainsail

[update_manager fluidd]
type: web
channel: stable
repo: fluidd-core/fluidd
path: /usr/data/fluidd
EOF

    log "Moonraker configuration created"
}

# Create Nginx configuration with proper structure
create_nginx_config() {
    print_status "Creating Nginx configuration"
    
    # Create Nginx directories
    mkdir -p /opt/etc/nginx
    
    # Remove any existing nginx.conf
    log "Removing any existing nginx.conf"
    rm -f /opt/etc/nginx/nginx.conf
    
    # Use available ports - ports 4408 and 4409, skipping port 80
    log "Creating new nginx.conf (using ports 4408 and 4409)"
    cat > /opt/etc/nginx/nginx.conf << 'EOF'
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    # Serve Fluidd on its own port
    server {
        listen 4408;
        root /usr/data/fluidd;
        
        location / {
            try_files $uri $uri/ /index.html;
        }
        
        location = /index.html {
            add_header Cache-Control "no-store, no-cache, must-revalidate";
        }
        
        location /websocket {
            proxy_pass http://127.0.0.1:7125/websocket;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
        
        location ~ ^/(printer|api|access|machine|server)/ {
            proxy_pass http://127.0.0.1:7125;
            proxy_http_version 1.1;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
    
    # Serve Mainsail on its own port
    server {
        listen 4409;
        root /usr/data/mainsail;
        
        location / {
            try_files $uri $uri/ /index.html;
        }
        
        location = /index.html {
            add_header Cache-Control "no-store, no-cache, must-revalidate";
        }
        
        location /websocket {
            proxy_pass http://127.0.0.1:7125/websocket;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
        
        location ~ ^/(printer|api|access|machine|server)/ {
            proxy_pass http://127.0.0.1:7125;
            proxy_http_version 1.1;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
    
    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }
}
EOF

    log "Nginx configuration created"
}

# Create Moonraker service startup script
create_moonraker_service() {
    print_status "Creating Moonraker service script"
    
    log "Creating start_moonraker.sh script"
    cat > "${USR_DATA}/start_moonraker.sh" << 'EOF'
#!/bin/sh

# Kill any existing Moonraker process
ps | grep moonraker | grep -v grep | awk '{print $1}' | xargs -r kill -9
ps | grep python | grep moonraker | grep -v grep | awk '{print $1}' | xargs -r kill -9
sleep 1

# Start Moonraker
cd /usr/data/moonraker
python3 /usr/data/moonraker/moonraker/moonraker.py -d /usr/data/printer_data > /usr/data/printer_data/logs/moonraker.log 2>&1 &

echo "Moonraker started!"
EOF

    chmod +x "${USR_DATA}/start_moonraker.sh"
    log "Moonraker service script created at ${USR_DATA}/start_moonraker.sh"
}

# Install UI files - USE GIT CLONE 
install_ui_files() {
    print_status "Installing UI files via git clone"
    
    # Create temporary directory
    TEMP_CLONE="/usr/data/tmp"
    mkdir -p "${TEMP_CLONE}"
    
    # Install Mainsail
    log "Installing Mainsail UI..."
    rm -rf "${MAINSAIL_DIR}"/*
    cd "${TEMP_CLONE}"
    log "Cloning Mainsail repository..."
    
    if git clone --depth=1 https://github.com/mainsail-crew/mainsail.git; then
        if [ -d "${TEMP_CLONE}/mainsail" ]; then
            # Check if dist directory exists (for production builds)
            if [ -d "${TEMP_CLONE}/mainsail/dist" ]; then
                cp -r "${TEMP_CLONE}/mainsail/dist/"* "${MAINSAIL_DIR}/"
            else
                # Copy all files if no dist directory
                cp -r "${TEMP_CLONE}/mainsail/"* "${MAINSAIL_DIR}/"
            fi
            rm -rf "${TEMP_CLONE}/mainsail"
            log "Mainsail UI files installed successfully"
        fi
    else
        log "Failed to clone Mainsail repository, will create minimal placeholder"
        echo "<!DOCTYPE html><html><head><title>Mainsail not installed</title></head><body><h1>Mainsail UI not installed</h1><p>Git clone failed. Please check your internet connection.</p></body></html>" > "${MAINSAIL_DIR}/index.html"
    fi
    
    # Install Fluidd
    log "Installing Fluidd UI..."
    rm -rf "${FLUIDD_DIR}"/*
    cd "${TEMP_CLONE}"
    log "Cloning Fluidd repository..."
    
    if git clone --depth=1 https://github.com/fluidd-core/fluidd.git; then
        if [ -d "${TEMP_CLONE}/fluidd" ]; then
            cp -r "${TEMP_CLONE}/fluidd/"* "${FLUIDD_DIR}/"
            rm -rf "${TEMP_CLONE}/fluidd"
            log "Fluidd UI files installed successfully"
        fi
    else
        log "Failed to clone Fluidd repository, will create minimal placeholder"
        echo "<!DOCTYPE html><html><head><title>Fluidd not installed</title></head><body><h1>Fluidd UI not installed</h1><p>Git clone failed. Please check your internet connection.</p></body></html>" > "${FLUIDD_DIR}/index.html"
    fi
}

# Start Moonraker
start_moonraker() {
    print_status "Starting Moonraker"
    
    "${USR_DATA}/start_moonraker.sh"
    
    # Check if Moonraker started
    sleep 2
    if ps | grep python | grep moonraker | grep -v grep >/dev/null; then
        log "Moonraker started successfully!"
    else
        log "Warning: Moonraker may not have started properly. Check logs at ${LOGS_DIR}/moonraker.log"
    fi
}

# Start Nginx
start_nginx() {
    print_status "Starting Nginx"
    
    # Start Nginx
    log "Starting Nginx"
    /opt/sbin/nginx
    
    # Check if Nginx started
    sleep 1
    if ps | grep nginx | grep -v grep >/dev/null; then
        log "Nginx started successfully!"
    else
        log "Warning: Nginx may not have started properly. Testing configuration..."
        /opt/sbin/nginx -t
    fi
}

# Main execution
main() {
    print_status "Starting automated installation of Moonraker, Nginx, and UI files for Creality K1"
    
    # Run all installation steps
    force_cleanup
    install_moonraker
    setup_venv
    create_moonraker_config
    create_nginx_config
    create_moonraker_service
    install_ui_files
    
    # Start services
    start_moonraker
    start_nginx
    
    print_status "Installation complete!"
    log ""
    log "Moonraker is running on port 7125"
    log "UI interfaces are installed and ready to use:"
    log "  • Fluidd: http://$(ip route get 1 | awk '{print $7;exit}'):4408"
    log "  • Mainsail: http://$(ip route get 1 | awk '{print $7;exit}'):4409"
    log ""
    log "Installation log saved to: ${SCRIPT_LOG}"
    log ""
    log "Enjoy!"
}

# Execute main function
main
