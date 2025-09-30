#!/bin/bash
#
# Linux Rescue Drive Builder
# Creates a bootable ISO with comprehensive system repair tools
#

set -e

# Configuration
WORK_DIR="$(pwd)/build"
ISO_NAME="linux-rescue-drive"
ISO_VERSION="1.0"
BASE_DISTRO="ubuntu-22.04-desktop-amd64.iso"
BASE_URL="https://releases.ubuntu.com/22.04/${BASE_DISTRO}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    log_info "Checking dependencies..."
    local deps=("squashfs-tools" "genisoimage" "syslinux-utils" "isolinux" "xorriso")
    
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null && ! dpkg -l | grep -q $dep; then
            log_error "Missing dependency: $dep"
            log_info "Installing $dep..."
            sudo apt-get update
            sudo apt-get install -y $dep
        fi
    done
    
    log_success "All dependencies satisfied"
}

download_base_iso() {
    log_info "Downloading base Ubuntu ISO..."
    if [ ! -f "${BASE_DISTRO}" ]; then
        wget -O "${BASE_DISTRO}" "${BASE_URL}"
    else
        log_warning "Base ISO already exists, skipping download"
    fi
}

extract_iso() {
    log_info "Extracting base ISO..."
    
    # Clean and create work directory
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"/{mnt,extract,new}
    
    # Mount the ISO
    sudo mount -o loop "$BASE_DISTRO" "$WORK_DIR/mnt"
    
    # Copy contents
    sudo rsync -av "$WORK_DIR/mnt/" "$WORK_DIR/extract/"
    
    # Unmount
    sudo umount "$WORK_DIR/mnt"
    
    # Make writable
    sudo chmod -R u+w "$WORK_DIR/extract"
}

customize_filesystem() {
    log_info "Customizing root filesystem..."
    
    # Extract squashfs
    sudo unsquashfs -d "$WORK_DIR/squashfs-root" "$WORK_DIR/extract/casper/filesystem.squashfs"
    
    # Prepare chroot environment
    sudo mount --bind /dev "$WORK_DIR/squashfs-root/dev"
    sudo mount --bind /proc "$WORK_DIR/squashfs-root/proc"
    sudo mount --bind /sys "$WORK_DIR/squashfs-root/sys"
    sudo mount --bind /run "$WORK_DIR/squashfs-root/run"
    
    # Copy DNS configuration
    sudo cp /etc/resolv.conf "$WORK_DIR/squashfs-root/etc/"
    
    # Install rescue tools
    sudo chroot "$WORK_DIR/squashfs-root" /bin/bash << 'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update

# System repair tools
apt-get install -y \
    testdisk photorec gparted \
    fsck.ext2 fsck.ext3 fsck.ext4 fsck.fat fsck.ntfs \
    ddrescue safecopy \
    chkrootkit rkhunter \
    memtest86+ \
    smartmontools hdparm \
    network-manager wireless-tools \
    openssh-server openssh-client \
    rsync wget curl \
    vim nano \
    htop iotop nethogs \
    strace ltrace \
    tcpdump wireshark-common \
    git \
    python3 python3-pip \
    build-essential \
    grub2-common grub-pc-bin grub-efi-amd64-bin \
    os-prober \
    lvm2 mdadm \
    cryptsetup \
    ntfs-3g exfat-fuse \
    zip unzip p7zip-full \
    screen tmux \
    tree file \
    lsof psmisc

# Additional Python tools for automation
pip3 install psutil

# Clean up
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*

# Enable SSH server
systemctl enable ssh

EOF

    # Copy our custom scripts
    sudo mkdir -p "$WORK_DIR/squashfs-root/opt/rescue"
    sudo cp -r autofix/* "$WORK_DIR/squashfs-root/opt/rescue/"
    sudo cp -r tools/* "$WORK_DIR/squashfs-root/opt/rescue/"
    sudo chmod +x "$WORK_DIR/squashfs-root/opt/rescue"/*.sh
    
    # Add rescue menu to desktop
    sudo mkdir -p "$WORK_DIR/squashfs-root/home/ubuntu/Desktop"
    sudo tee "$WORK_DIR/squashfs-root/home/ubuntu/Desktop/rescue-tools.desktop" > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Name=Linux Rescue Tools
Comment=Automated system repair and diagnostics
Exec=/opt/rescue/rescue-menu.sh
Icon=applications-system
Terminal=true
Type=Application
Categories=System;
EOF

    # Cleanup chroot
    sudo umount "$WORK_DIR/squashfs-root/dev"
    sudo umount "$WORK_DIR/squashfs-root/proc"
    sudo umount "$WORK_DIR/squashfs-root/sys"
    sudo umount "$WORK_DIR/squashfs-root/run"
}

rebuild_squashfs() {
    log_info "Rebuilding squashfs filesystem..."
    
    # Remove old squashfs
    sudo rm "$WORK_DIR/extract/casper/filesystem.squashfs"
    
    # Create new squashfs
    sudo mksquashfs "$WORK_DIR/squashfs-root" "$WORK_DIR/extract/casper/filesystem.squashfs" -comp xz
    
    # Update filesystem size
    printf $(sudo du -sx --block-size=1 "$WORK_DIR/squashfs-root" | cut -f1) | sudo tee "$WORK_DIR/extract/casper/filesystem.size"
    
    # Update MD5 sums
    cd "$WORK_DIR/extract"
    sudo find . -type f -print0 | sudo xargs -0 md5sum | grep -v isolinux/boot.cat | sudo tee md5sum.txt
}

create_iso() {
    log_info "Creating final ISO..."
    
    cd "$WORK_DIR/extract"
    
    sudo xorriso -as mkisofs \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -c isolinux/boot.cat \
        -b isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -o "../../${ISO_NAME}-${ISO_VERSION}.iso" \
        .
    
    cd ../..
}

cleanup() {
    log_info "Cleaning up..."
    sudo rm -rf "$WORK_DIR"
}

main() {
    log_info "Starting Linux Rescue Drive build process..."
    
    check_dependencies
    download_base_iso
    extract_iso
    customize_filesystem
    rebuild_squashfs
    create_iso
    cleanup
    
    log_success "Linux Rescue Drive ISO created: ${ISO_NAME}-${ISO_VERSION}.iso"
    log_info "Use create-usb.sh to write this ISO to a USB drive"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root (it will use sudo when needed)"
   exit 1
fi

main "$@"