#!/bin/bash
set -eou pipefail

BUILDROOT_VERSION="2023.02.2"
# Required packages for Buildroot
PACKAGES="build-essential libncurses5-dev wget cpio unzip rsync bc bison flex file patch libtool automake git python3 qemu-system-x86 libelf-dev"

echo "[*] Installing required packages..."

# If this is a multi-user system odds are tzdata is already configured
if [ "$(id -u)" -ne 0 ]; then
    sudo apt update
    sudo apt install -y ${PACKAGES}
else
    # Avoid tzdata prompting in container
    export DEBIAN_FRONTEND=noninteractive
    apt update && \
    echo "tzdata tzdata/Areas select Etc" | debconf-set-selections && \
    echo "tzdata tzdata/Zones/Etc select UTC" | debconf-set-selections && \
    apt install -y ${PACKAGES}
fi

# Download Buildroot

echo "[*] Downloading Buildroot..."
wget -q https://buildroot.org/downloads/buildroot-$BUILDROOT_VERSION.tar.gz
tar xf buildroot-$BUILDROOT_VERSION.tar.gz
cd buildroot-$BUILDROOT_VERSION

# Create custom init script that prints Hello World
mkdir -p board/custom/overlay/etc/init.d
cat > board/custom/overlay/etc/init.d/rcS << 'EOF'
#!/bin/sh
echo ""
echo "##############################"
echo "##                          ##"
echo "##      Hello, World!       ##"
echo "##                          ##"
echo "##############################"
echo ""
echo "Starting shell..."
exec /bin/sh
EOF
chmod +x board/custom/overlay/etc/init.d/rcS

# Create custom Buildroot configuration
cat > configs/custom_qemu_x86_64_defconfig << 'EOF'
# Buildroot
BR2_x86_64=y
BR2_TOOLCHAIN_BUILDROOT_GLIBC=y
BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_5_15=y
BR2_TOOLCHAIN_BUILDROOT_CXX=y
BR2_TARGET_GENERIC_HOSTNAME="buildroot"
BR2_TARGET_GENERIC_ISSUE="Welcome to Buildroot"
BR2_ROOTFS_OVERLAY="board/custom/overlay"
# Init
BR2_INIT_NONE=y
# Kernel
BR2_LINUX_KERNEL=y
BR2_LINUX_KERNEL_CUSTOM_VERSION=y
BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="5.15.89"
BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="board/qemu/x86_64/linux.config"
BR2_TARGET_ROOTFS_CPIO=y
BR2_TARGET_ROOTFS_CPIO_GZIP=y
# BR2_TARGET_ROOTFS_TAR is not set
EOF

# Build configuration
echo "[*] Building Buildroot system..."
make custom_qemu_x86_64_defconfig
make -j$(nproc)

echo "[*] Launching system with QEMU..."

qemu-system-x86_64 \
    -M pc \
    -kernel output/images/bzImage \
    -initrd output/images/rootfs.cpio.gz \
    -append "console=ttyS0 panic=1 rdinit=/etc/init.d/rcS" \
    -nographic \
    -m 256


