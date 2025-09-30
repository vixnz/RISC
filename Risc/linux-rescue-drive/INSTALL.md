# Installation Guide

Get started with the Linux Rescue Drive in just a few steps.

## Prerequisites

- **System**: Linux (Ubuntu 18.04+ recommended)
- **Disk Space**: 10GB+
- **USB Drive**: 8GB+
- **Internet**: Required for downloading base ISO
- **Access**: Root/sudo privileges

## Install Dependencies

### Ubuntu/Debian:
```bash
sudo apt update && sudo apt install -y squashfs-tools genisoimage syslinux-utils isolinux xorriso wget rsync
```

### CentOS/RHEL/Fedora:
```bash
sudo dnf install -y squashfs-tools genisoimage syslinux xorriso wget rsync
```

### Arch Linux:
```bash
sudo pacman -S squashfs-tools cdrtools syslinux libisoburn wget rsync
```

## Build the Rescue ISO

1. **Clone the Project**:
   ```bash
   git clone <repository-url> linux-rescue-drive
   cd linux-rescue-drive
   ```

2. **Make Scripts Executable**:
   ```bash
   chmod +x *.sh autofix/*.sh
   ```

3. **Run the Build Script**:
   ```bash
   ./build-rescue-iso.sh
   ```

   - Downloads and customizes the base ISO
   - Installs rescue tools
   - Creates `linux-rescue-drive-1.0.iso`

4. **Verify the ISO**:
   ```bash
   ls -lh linux-rescue-drive-1.0.iso
   file linux-rescue-drive-1.0.iso
   ```

## Create Bootable USB

1. **Identify USB Drive**:
   ```bash
   lsblk
   ```
   Find your USB device (e.g., `/dev/sdb`).

2. **Write ISO to USB**:
   ```bash
   ./create-usb.sh linux-rescue-drive-1.0.iso /dev/sdX
   ```
   Replace `/dev/sdX` with your USB device. ⚠️ This erases all data on the USB.

## Boot and Use

1. **Boot from USB**:
   - Insert the USB drive into the target computer.
   - Restart and select the USB drive from the boot menu.

2. **Select Boot Option**:
   - "Linux Rescue Drive" for standard boot.
   - "Safe Mode" for graphics issues.

3. **Use the Rescue Menu**:
   - Quick AutoFix, Boot Repair, Filesystem Check, Hardware Diagnostics, and more.

## Troubleshooting

- **Build Issues**: Check dependencies, disk space, and internet connection.
- **USB Not Booting**: Verify boot order, disable Secure Boot, or try another USB port.
- **Runtime Issues**: Ensure root privileges and sufficient RAM.

# GitHub Installation Instructions

Follow these simple steps to set up the Linux Rescue Drive from GitHub.

## Step 1: Clone the Repository

1. Open a terminal.
2. Run the following command:
   ```bash
   git clone https://github.com/vixnz/RISC.git
   ```
3. Navigate to the project folder:
   ```bash
   cd RISC
   ```

## Step 2: Make Scripts Executable

Run this command to ensure all scripts are ready to execute:
```bash
chmod +x *.sh autofix/*.sh
```

## Step 3: Build the Rescue ISO

Run the build script to create the ISO:
```bash
./build-rescue-iso.sh
```

## Step 4: Create Bootable USB

1. Identify your USB drive:
   ```bash
   lsblk
   ```
2. Write the ISO to the USB drive:
   ```bash
   ./create-usb.sh linux-rescue-drive-1.0.iso /dev/sdX
   ```
   Replace `/dev/sdX` with your USB device. ⚠️ This will erase all data on the USB.

---

You're all set! Boot from the USB to start using the Linux Rescue Drive.