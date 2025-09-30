# Linux Rescue Drive

A bootable USB rescue system to fix common Linux issues.

## Features

- **Quick AutoFix**: Automatically detects and repairs system issues (filesystem, bootloader, network, packages).
- **Comprehensive Tools**: Boot repair, filesystem check, hardware diagnostics, network repair, package management, security scan, data recovery, and system info.
- **Manual Tools**: Includes GParted, TestDisk, PhotoRec, Memtest86+, and network utilities.

## Quick Start

### Build the Rescue ISO
1. **Install Dependencies**:
   ```bash
   sudo apt update && sudo apt install squashfs-tools genisoimage syslinux-utils isolinux xorriso wget
   ```
2. **Build the ISO**:
   ```bash
   ./build-rescue-iso.sh
   ```

### Create Bootable USB
1. **Write ISO to USB**:
   ```bash
   ./create-usb.sh linux-rescue-drive-1.0.iso /dev/sdX
   ```
   ⚠️ Replace `/dev/sdX` with your USB device. This erases all data on the USB.
2. **Boot from USB**:
   - Insert USB and boot from it.
   - Select "Linux Rescue Drive" from the boot menu.

## Usage

### Main Menu Options
1. **Quick AutoFix**: Automatic repair of common issues.
2. **Boot Repair**: Fix GRUB and bootloader problems.
3. **Filesystem Check**: Repair filesystem errors.
4. **Hardware Diagnostics**: Test memory, CPU, storage, and network.
5. **Network Repair**: Fix connectivity issues.
6. **Package Management**: Repair broken packages.
7. **Security Scan**: Detect malware and vulnerabilities.
8. **Data Recovery**: Recover deleted files and partitions.
9. **System Info**: View detailed system information.
10. **Manual Tools**: Access individual utilities.

## System Requirements

- **RAM**: 4GB (8GB recommended)
- **CPU**: x86_64 (64-bit)
- **USB**: 8GB+ drive
- **Supported Systems**: Most Linux distributions and filesystems.

## Troubleshooting

- **Build Issues**: Check dependencies, disk space, and internet connection.
- **Boot Issues**: Verify USB creation, boot order, and Secure Boot settings.
- **Runtime Issues**: Ensure root privileges and sufficient RAM.

## License

This project is licensed under a custom license by Vixnz ([GitHub](https://github.com/vixnz)). Redistribution and modification are prohibited without explicit permission.

---

**Linux Rescue Drive** - Your go-to solution for Linux system recovery!