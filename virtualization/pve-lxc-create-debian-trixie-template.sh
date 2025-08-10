#!/usr/bin/env bash

# Debian Trixie LXC Template Creator for Proxmox
# Run directly on Proxmox host
# This corrected version is compatible with Proxmox's network management.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

msg_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
msg_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
msg_error() { echo -e "${RED}[ERROR]${NC} $1"; }
msg_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Configuration
TEMPLATE_NAME="debian-trixie-proxmox_$(date +%Y%m%d)_amd64.tar.zst"
WORK_DIR="/var/lib/vz/template/build"
TEMPLATE_DIR="/var/lib/vz/template/cache"
DEBIAN_MIRROR="http://deb.debian.org/debian"

# Cleanup function
cleanup() {
    if [[ -d "${WORK_DIR}/rootfs" ]]; then
        msg_info "Cleaning up build directory"
        rm -rf "${WORK_DIR}"
    fi
}
trap cleanup EXIT

# Check if running on Proxmox (multiple possible locations)
if [[ ! -f "/usr/bin/pct" ]] && [[ ! -f "/usr/sbin/pct" ]] && ! command -v pct >/dev/null 2>&1; then
    msg_error "This script is designed to run on Proxmox VE (pct command not found)"
    exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    msg_error "This script must be run as root"
    exit 1
fi

msg_info "Creating Debian Trixie LXC template on Proxmox"
msg_info "Template will be: ${TEMPLATE_NAME}"

# Create work directory
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Install debootstrap if not present
if ! command -v debootstrap >/dev/null 2>&1; then
    msg_info "Installing debootstrap"
    apt update && apt install -y debootstrap
fi

# Bootstrap Debian Trixie
msg_info "Bootstrapping Debian Trixie base system"
debootstrap --arch=amd64 --variant=minbase \
    --include=systemd,systemd-sysv,locales,debian-archive-keyring,ca-certificates \
    trixie rootfs "${DEBIAN_MIRROR}"

msg_ok "Base system bootstrap completed"

# Configure the system
msg_info "Configuring system"

# Mount necessary filesystems for chroot
mount -t proc proc rootfs/proc
mount -t sysfs sysfs rootfs/sys
mount -o bind /dev rootfs/dev
mount -o bind /dev/pts rootfs/dev/pts

# Cleanup function for mounts
cleanup_mounts() {
    umount -l rootfs/dev/pts 2>/dev/null || true
    umount -l rootfs/dev 2>/dev/null || true
    umount -l rootfs/sys 2>/dev/null || true
    umount -l rootfs/proc 2>/dev/null || true
}

# Update trap to include mount cleanup
trap 'cleanup_mounts; cleanup' EXIT

# Configure system in chroot
chroot rootfs /bin/bash << 'CHROOT_EOF'
set -e

# Remove old sources format
rm -f /etc/apt/sources.list

# Create modern DEB822 format APT sources
mkdir -p /etc/apt/sources.list.d

cat > /etc/apt/sources.list.d/debian.sources << 'APT_EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
APT_EOF

cat > /etc/apt/sources.list.d/debian-security.sources << 'APT_EOF'
Types: deb
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
APT_EOF

# Update package lists
apt update

# Install essential packages for a Proxmox-compatible container
DEBIAN_FRONTEND=noninteractive apt install -y \
    apt-utils \
    dialog \
    iproute2 \
    ifupdown \
    isc-dhcp-client \
    netbase \
    net-tools \
    iputils-ping \
    wget \
    curl \
    nano \
    less \
    bash-completion \
    openssh-server \
    dbus

# Configure locales
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# --- Network Configuration Removed ---
# The following sections for systemd-networkd and systemd-resolved have been
# removed. Proxmox manages networking via /etc/network/interfaces, and
# enabling systemd-networkd here would cause a conflict, preventing
# Proxmox from applying network settings from the GUI/API.

# Disable hardware-specific services for containers
systemctl mask systemd-udevd.service
systemctl mask systemd-udevd-control.socket
systemctl mask systemd-udevd-kernel.socket
systemctl mask systemd-modules-load.service
systemctl mask systemd-machine-id-commit.service

# Enable SSH
systemctl enable ssh

# Create a clean interfaces file for Proxmox to manage.
# Proxmox will automatically add the configuration for eth0 to this file.
cat > /etc/network/interfaces << 'IFACE_EOF'
auto lo
iface lo inet loopback
IFACE_EOF

# Clean up
apt clean
apt autoremove -y

# Remove logs and temporary files
find /var/log -type f -delete 2>/dev/null || true
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
rm -rf /var/cache/apt/* /var/lib/apt/lists/* 2>/dev/null || true

# Clear history and machine ID
rm -f /root/.bash_history
echo -n > /etc/machine-id

# Remove SSH host keys (regenerated on first boot)
rm -f /etc/ssh/ssh_host_*

# Clear systemd journal
journalctl --vacuum-time=1s 2>/dev/null || true

echo "System configuration completed successfully"
CHROOT_EOF

msg_ok "System configuration completed"

# Cleanup mounts before creating archive
cleanup_mounts

msg_info "Creating template archive"

# Validate rootfs
if [[ ! -f "rootfs/bin/bash" ]]; then
    msg_error "Invalid rootfs - missing essential files"
    exit 1
fi

# Create template archive
if ! tar --zstd -cf "${TEMPLATE_DIR}/${TEMPLATE_NAME}" -C rootfs .; then
    msg_error "Failed to create template archive"
    exit 1
fi

msg_ok "Template created successfully"

# Validate template
msg_info "Validating template"
if tar --zstd -tf "${TEMPLATE_DIR}/${TEMPLATE_NAME}" >/dev/null 2>&1; then
    msg_ok "Template validation passed"
else
    msg_error "Template validation failed"
    exit 1
fi

# Get template size
TEMPLATE_SIZE=$(du -h "${TEMPLATE_DIR}/${TEMPLATE_NAME}" | cut -f1)

msg_ok "Debian Trixie template creation completed!"
echo ""
echo -e "${GREEN}Template details:${NC}"
echo -e "  Name: ${TEMPLATE_NAME}"
echo -e "  Location: ${TEMPLATE_DIR}/${TEMPLATE_NAME}"
echo -e "  Size: ${TEMPLATE_SIZE}"
echo ""
echo -e "${BLUE}Test the template:${NC}"
echo -e "  pct create 999 local:vztmpl/${TEMPLATE_NAME} --memory 1024 --net0 name=eth0,bridge=vmbr0,ip=dhcp"
echo -e "  pct start 999"
echo -e "  pct enter 999"
echo ""
echo -e "${YELLOW}Don't forget to destroy the test container:${NC}"
echo -e "  pct stop 999 && pct destroy 999"
