#!/usr/bin/env bash
set -xeuo pipefail

# =============================================================================
# SBC / BOARD-SPECIFIC SUPPORT
# =============================================================================
# Installs firmware, device trees, and boot packages for specific ARM SBC families.
# Controlled by the BOARD_TARGET build argument.

BOARD_TARGET="${BOARD_TARGET:-generic}"

case "${BOARD_TARGET}" in
    generic)
        echo "Generic aarch64 target — standard UEFI boot support"

        # Ensure UEFI boot support packages are present
        dnf5 install -y \
            efibootmgr \
            grub2-efi-aa64 \
            shim-aa64 \
            linux-firmware
        ;;

    rpi5)
        echo "============================================================"
        echo "WARNING: Raspberry Pi 5 support is EXPERIMENTAL"
        echo "Fedora 43 mainline kernel has limited RPi 5 support."
        echo "Some peripherals (USB, GPIO) may not work correctly."
        echo "============================================================"

        # Base UEFI packages
        dnf5 install -y \
            efibootmgr \
            grub2-efi-aa64 \
            shim-aa64 \
            linux-firmware

        # RPi-specific firmware (install if available)
        dnf5 install -y bcm283x-firmware 2>/dev/null || \
            echo "WARNING: bcm283x-firmware not found in repos, RPi 5 support may be limited"
        ;;

    rockchip)
        echo "============================================================"
        echo "WARNING: Rockchip support is EXPERIMENTAL"
        echo "RK3588 device trees are in the Fedora kernel (6.15+)."
        echo "Board-specific firmware may need manual installation."
        echo "============================================================"

        # Base UEFI packages
        dnf5 install -y \
            efibootmgr \
            grub2-efi-aa64 \
            shim-aa64 \
            linux-firmware

        # Rockchip RK3588 boards (Rock 5B, Orange Pi 5) use mainline device trees
        # No additional firmware packages needed for basic boot in Fedora 43
        ;;

    *)
        echo "ERROR: Unknown BOARD_TARGET: ${BOARD_TARGET}"
        echo "Valid targets: generic, rpi5, rockchip"
        exit 1
        ;;
esac

echo "Board support configured for: ${BOARD_TARGET}"
