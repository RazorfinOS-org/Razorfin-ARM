#!/usr/bin/env bash
set -xeuo pipefail

# =============================================================================
# FEX-EMU — x86/x86-64 EMULATION FOR ARM64
# =============================================================================
# FEX-Emu translates x86/x86-64 instructions to ARM64, enabling Steam and
# x86 Linux games to run on aarch64 hardware. Valve funds FEX development
# for the Steam Frame headset.

# Core FEX-Emu installation (fex-emu, fex-emu-rootfs-fedora, muvm, hidpipe)
dnf5 install -y @x86-emulation

# FEX thunks — forwards Vulkan/OpenGL calls to native ARM64 Mesa drivers
# instead of emulating them. Critical for GPU performance.
dnf5 install -y fex-emu-thunks

# =============================================================================
# NATIVE ARM64 GPU DRIVERS
# =============================================================================

dnf5 install -y \
    mesa-vulkan-drivers \
    mesa-dri-drivers \
    mesa-va-drivers \
    vulkan-tools \
    vulkan-loader

# =============================================================================
# GAMING TOOLS
# =============================================================================

# Gamescope — Valve's micro-compositor (wrap in check for aarch64 availability)
if dnf5 list gamescope --available 2>/dev/null | grep -q aarch64; then
    dnf5 install -y gamescope
else
    echo "WARNING: gamescope not available for aarch64 in this repo, skipping"
fi

# MangoHud — performance overlay
if dnf5 list mangohud --available 2>/dev/null | grep -q aarch64; then
    dnf5 install -y mangohud
else
    echo "WARNING: mangohud not available for aarch64, skipping"
fi

# GameMode — performance optimizer
dnf5 install -y gamemode

# =============================================================================
# STEAM INTEGRATION
# =============================================================================
# Steam is an x86-64 application. FEX-Emu translates it for ARM64.
# We provide a wrapper script and .desktop file for easy launching.

cat > /usr/bin/razorfin-steam << 'STEAMEOF'
#!/usr/bin/bash
# Launch Steam via FEX-Emu on ARM64
# Steam is an x86-64 application; FEX translates it to run on aarch64

# Verify FEX is functional
if ! command -v FEXBash &>/dev/null; then
    echo "ERROR: FEX-Emu is not installed. Cannot run Steam on ARM64 without it."
    exit 1
fi

# Verify 4K page size (FEX requirement)
PAGE_SIZE=$(getconf PAGE_SIZE)
if [[ "${PAGE_SIZE}" != "4096" ]]; then
    echo "WARNING: FEX-Emu requires a 4K page-size kernel."
    echo "Current page size: ${PAGE_SIZE} bytes."
    echo "FEX may use muvm to work around this, but performance may vary."
fi

exec FEXBash -c "steam $*"
STEAMEOF
chmod +x /usr/bin/razorfin-steam

# Desktop entry for Steam via FEX
mkdir -p /usr/share/applications
cat > /usr/share/applications/razorfin-steam.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Steam (FEX)
Comment=Launch Steam via FEX-Emu on ARM64
Exec=razorfin-steam %U
Icon=steam
Terminal=false
Type=Application
Categories=Game;
MimeType=x-scheme-handler/steam;x-scheme-handler/steamlink;
Keywords=gaming;valve;proton;
DESKTOPEOF

echo "Gaming stack installation complete."
echo "FEX-Emu installed for x86/x86-64 translation."
echo "Launch Steam with: razorfin-steam"
