#!/bin/bash
set -eou pipefail

# Check if a script name was provided; if not, default to simpler/faster one
if [ "$#" -ge 1 ]; then
    SCRIPT_NAME="$1"
else
    SCRIPT_NAME="busybox-kernel-qemu.sh"
fi

# Display status in color
log() {
    echo -e "\n\033[1;34m[*] $1\033[0m"
}

# Check if podman is installed
if ! command -v podman &> /dev/null; then
    log "Podman not found. Installing podman..."
    sudo apt-get update
    sudo apt-get install -y podman
fi

# Test on Ubuntu 
test_ubuntu() {
    local version=$1
    log "Testing on Ubuntu $version"
    
    # Create a container with Ubuntu
    container_name="buildroot-test-ubuntu-$version"
    
    # Remove container if it already exists
    sudo podman rm -f $container_name 2>/dev/null || true
    
    # Create new container
    log "Creating Ubuntu $version container..."
    sudo podman run --cap-add=MKNOD --memory=8g --memory-swap=8g --name $container_name -d ubuntu:$version sleep infinity
    
    # Copy script to container
    log "Copying build script to container..."
    sudo podman cp $SCRIPT_NAME $container_name:/root/
    
    # Run the script
    log "Running build script in Ubuntu $version container..."
    sudo podman exec -it $container_name bash -c "cd /root && chmod a+x $SCRIPT_NAME && ./$SCRIPT_NAME"
    
    # Clean up
    log "Cleaning up container..."
    sudo podman stop $container_name
    sudo podman rm -f $container_name
}

# Test on both Ubuntu versions
log "Starting tests for Ubuntu 20.04 and 22.04"
test_ubuntu "20.04"
test_ubuntu "22.04"

log "All tests completed!"
