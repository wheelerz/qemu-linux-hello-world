#!/bin/bash
set -euo pipefail

# --- PACKAGE INSTALLATION FUNCTION ---
MISSING_PACKAGES="qemu-system busybox wget dpkg cpio gzip build-essential"

echo "Attempting to install packages via apt..."
# If this is a multi-user system odds are tzdata is already configured
if [ "$(id -u)" -ne 0 ]; then
    sudo apt update
    sudo apt install -y ${MISSING_PACKAGES}
else
    # Avoid tzdata prompting in container
    export DEBIAN_FRONTEND=noninteractive
    apt update && \
    echo "tzdata tzdata/Areas select Etc" | debconf-set-selections && \
    echo "tzdata tzdata/Zones/Etc select UTC" | debconf-set-selections && \
    apt install -y ${MISSING_PACKAGES}
fi


# --- CONFIGURATION ---

# Specify the kernel version and corresponding directory on the mainline archive.
KERNEL_VERSION="6.13.2"
KERNEL_ABBR_VER="061302"
KERNEL_DATE="202502081010"

DEB_FILE=linux-image-unsigned-${KERNEL_VERSION}-${KERNEL_ABBR_VER}-generic_${KERNEL_VERSION}-${KERNEL_ABBR_VER}.${KERNEL_DATE}_amd64.deb
KERNEL_DIR="v${KERNEL_VERSION}"
# Name of the .deb package from the mainline archive.
# Construct the download URL.
KERNEL_URL="https://kernel.ubuntu.com/~kernel-ppa/mainline/${KERNEL_DIR}/amd64/${DEB_FILE}"
# Local filename for the downloaded .deb package.
LOCAL_DEB="${DEB_FILE}"
# Directory where the .deb file will be extracted.
EXTRACT_DIR="./kernel_extract"
# Final kernel image file name.
KERNEL_IMG="bzImage"

# --- DOWNLOAD KERNEL DEB PACKAGE ---

if [ ! -f "${LOCAL_DEB}" ]; then
    echo "Downloading kernel .deb package from ${KERNEL_URL}..."
    wget -O "${LOCAL_DEB}" "${KERNEL_URL}"
else
    echo "Kernel .deb package ${LOCAL_DEB} already exists, skipping download."
fi

# --- EXTRACT THE KERNEL IMAGE (bzImage) ---

echo "Extracting the kernel image from ${LOCAL_DEB}..."
rm -rf "${EXTRACT_DIR}"
mkdir -p "${EXTRACT_DIR}"
dpkg-deb -x "${LOCAL_DEB}" "${EXTRACT_DIR}"

EXTRACTED_KERNEL_IMG=$(find "${EXTRACT_DIR}/boot" -type f -name "vmlinuz-${KERNEL_VERSION}-${KERNEL_ABBR_VER}-generic" | head -n 1)
if [ -z "${EXTRACTED_KERNEL_IMG}" ]; then
    echo "Error: Could not find the kernel image in the extracted package." >&2
    exit 1
fi

echo "Kernel image found: ${EXTRACTED_KERNEL_IMG}"
cp "${EXTRACTED_KERNEL_IMG}" "${KERNEL_IMG}"
echo "Kernel image copied to: ${KERNEL_IMG}"

# --- INITRAMFS BUILD ---

WORKDIR="$(pwd)"
INITRAMFS_DIR="${WORKDIR}/initramfs"
INITRAMFS_IMG="${WORKDIR}/initramfs.gz"

echo "Creating initramfs build directory in ${INITRAMFS_DIR}..."
rm -rf "${INITRAMFS_DIR}"
mkdir -p "${INITRAMFS_DIR}"/{bin,sbin,etc,proc,sys,dev}

# Configuration
BUSYBOX_VERSION="1.36.1"
WORKDIR=$(pwd)
BUSYBOX_ARCHIVE="busybox-${BUSYBOX_VERSION}.tar.bz2"
BUSYBOX_URL="https://busybox.net/downloads/${BUSYBOX_ARCHIVE}"

# Download BusyBox
echo "Downloading BusyBox ${BUSYBOX_VERSION}..."
wget "${BUSYBOX_URL}"

# Extract archive
echo "Extracting archive..."
tar xjf "${BUSYBOX_ARCHIVE}"
cd "busybox-${BUSYBOX_VERSION}"

# Configure BusyBox
# Note: Modify these options based on your needs
echo "Configuring BusyBox..."
make defconfig
# Build static binary and disable TC because of build errors
sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config
sed -i 's/CONFIG_FEATURE_TC_INGRESS=y/# CONFIG_FEATURE_TC_INGRESS is not set/' .config
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

# Build BusyBox
echo "Building BusyBox..."
make -j"$(nproc)"

echo "BusyBox binary is located at: ${WORKDIR}/busybox-${BUSYBOX_VERSION}/busybox"
cp "${WORKDIR}/busybox-${BUSYBOX_VERSION}/busybox"  "${INITRAMFS_DIR}/bin/"
echo "Busybox installed!"

cd "${INITRAMFS_DIR}/bin"
for app in sh ls mount echo poweroff; do
    [ -e "$app" ] || ln -s busybox "$app"
done
cd "${WORKDIR}"

cat > "${INITRAMFS_DIR}/init" << 'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
echo "Hello, world!"
exec /bin/sh
EOF
chmod a+x "${INITRAMFS_DIR}/init"

if [ "$(id -u)" -ne 0 ]; then
    echo "Creating device nodes (using sudo)..."
    sudo mknod -m 622 "${INITRAMFS_DIR}/dev/console" c 5 1
    sudo mknod -m 666 "${INITRAMFS_DIR}/dev/null" c 1 3
else
    echo "Creating device nodes..."
    mknod -m 622 "${INITRAMFS_DIR}/dev/console" c 5 1
    mknod -m 666 "${INITRAMFS_DIR}/dev/null" c 1 3
fi

echo "Creating initramfs image..."
(cd "${INITRAMFS_DIR}" && find . | cpio -H newc -o | gzip > "${INITRAMFS_IMG}")
echo "Initramfs image created: ${INITRAMFS_IMG}"

# --- RUN QEMU ---

echo "Starting QEMU..."
qemu-system-x86_64 \
    -kernel "${KERNEL_IMG}" \
    -initrd "${INITRAMFS_IMG}" \
    -append "console=ttyS0 root=/dev/ram" \
    -nographic

