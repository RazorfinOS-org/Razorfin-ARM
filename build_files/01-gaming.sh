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

# Remove binfmt-dispatcher — its argv handling is broken with POCF flags
# (AsahiLinux/binfmt-dispatcher#6). On 4K-page kernels, FEX registers
# directly via /usr/lib/binfmt.d/FEX-x86*.conf without needing the dispatcher.
# Use rpm --noscripts because the postun scriptlet tries to restart systemd-binfmt
# which isn't available during container builds.
rpm -e --noscripts binfmt-dispatcher

# Remove QEMU user-static for x86 — the @x86-emulation group pulls it in,
# but its binfmt entries (qemu-x86_64-static.conf) conflict with FEX's.
# QEMU's user-mode emulation is much slower than FEX's JIT and lacks thunk support.
rpm -e --noscripts qemu-user-static-x86

# FEX thunks — forwards Vulkan/OpenGL calls to native ARM64 Mesa drivers
# instead of emulating them. Critical for GPU performance.
dnf5 install -y fex-emu-thunks

# =============================================================================
# FEX-EMU VERSION CHECK
# =============================================================================
# Warn at build time if the installed FEX version is below our tested baseline.

FEX_MIN_VERSION="2502" # FEX-Emu 25.02 (February 2025)
FEX_INSTALLED=$(rpm -q --queryformat='%{VERSION}' fex-emu 2>/dev/null | tr -d '.')
if [[ -n "${FEX_INSTALLED}" && "${FEX_INSTALLED}" -lt "${FEX_MIN_VERSION}" ]]; then
    echo "=========================================================="
    echo "WARNING: FEX-Emu $(rpm -q --queryformat='%{VERSION}' fex-emu) is older than baseline 25.02"
    echo "Some thunks or AppConfig features may not work correctly."
    echo "=========================================================="
else
    echo "FEX-Emu version: $(rpm -q --queryformat='%{VERSION}' fex-emu)"
fi

# =============================================================================
# FEX CONFIGURATION — GLOBAL THUNK ENABLEMENT
# =============================================================================
# Point FEX to the thunk libraries installed by fex-emu-thunks so that
# Vulkan/GL calls are forwarded to native ARM64 Mesa by default.

# Merge thunk settings into existing Config.json (preserves RootFS path from RPM)
FEX_CONFIG="/usr/share/fex-emu/Config.json"
if [[ -f "${FEX_CONFIG}" ]]; then
    python3 -c "
import json, sys
with open('${FEX_CONFIG}') as f:
    existing = json.load(f)
with open('/ctx/build/gaming/fex-global.json') as f:
    overlay = json.load(f)
existing.setdefault('Config', {}).update(overlay.get('Config', {}))
with open('${FEX_CONFIG}', 'w') as f:
    json.dump(existing, f, indent=2)
"
    echo "Merged thunk paths into existing FEX config"
else
    cp /ctx/build/gaming/fex-global.json "${FEX_CONFIG}"
    echo "Installed FEX config (no existing config found)"
fi

# =============================================================================
# FEX APPCONFIG — PER-APPLICATION PROFILES
# =============================================================================
# Pre-tested per-game configs from https://github.com/FEX-Emu/AppConfig
# that enable/disable thunks and set TSO options for specific games.

APPCONFIG_SRC="/ctx/build/fex-appconfig"
APPCONFIG_DST="/usr/share/fex-emu/AppConfig"

if [[ -d "${APPCONFIG_SRC}" ]]; then
    mkdir -p "${APPCONFIG_DST}"
    find "${APPCONFIG_SRC}" -name '*.json' -exec cp {} "${APPCONFIG_DST}/" \;
    echo "Installed $(find "${APPCONFIG_DST}" -name '*.json' | wc -l) FEX AppConfig profiles"
else
    echo "WARNING: FEX AppConfig not found at ${APPCONFIG_SRC} (submodule not initialized?)"
fi

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
# KERNEL & SYSTEM TUNING
# =============================================================================
# Performance tuning for gaming workloads. Values match Bazzite's production
# configuration (proven on millions of Steam Deck devices).

cp /ctx/build/gaming/99-razorfin-gaming.conf /usr/lib/sysctl.d/99-razorfin-gaming.conf
echo "Installed gaming sysctl tuning"

mkdir -p /etc/security/limits.d
cp /ctx/build/gaming/15-memlock.conf /etc/security/limits.d/15-memlock.conf
echo "Installed memlock limits for Proton/Wine"

# Verify ZRAM is available (vm.swappiness=180 depends on it)
if ! rpm -q zram-generator &>/dev/null && ! rpm -q systemd-zram-generator &>/dev/null; then
    echo "=========================================================="
    echo "WARNING: No ZRAM generator found!"
    echo "vm.swappiness=180 assumes ZRAM is active."
    echo "Without ZRAM, this value will cause excessive swap thrashing."
    echo "=========================================================="
fi

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
# Razorfin Steam Launcher — FEX-Emu with bootstrap and hardware detection

STEAM_DIR="${HOME}/.local/share/Steam"
STEAM_BOOTSTRAP_URL="https://cdn.fastly.steamstatic.com/client/installer/steam.deb"
STEAM_BOOTSTRAP_DIR="${HOME}/.local/share/razorfin/steam-bootstrap"

# ── FEX-Emu check ──────────────────────────────────────────────────
if ! command -v FEXBash &>/dev/null; then
    echo "ERROR: FEX-Emu is not installed."
    exit 1
fi

PAGE_SIZE=$(getconf PAGE_SIZE)
if [[ "${PAGE_SIZE}" != "4096" ]]; then
    echo "WARNING: FEX-Emu requires 4K pages. Current: ${PAGE_SIZE} bytes."
    echo "FEX may use muvm to work around this."
fi

# ── TSO detection ───────────────────────────────────────────────────
if [[ -f /proc/cpuinfo ]]; then
    CPU_FEATURES=$(grep -m1 '^Features' /proc/cpuinfo 2>/dev/null | cut -d: -f2 || true)
    if echo "${CPU_FEATURES}" | grep -qw 'lrcpc2'; then
        echo "TSO: Hardware LRCPC2 detected — native x86 memory ordering"
    elif echo "${CPU_FEATURES}" | grep -qw 'lrcpc'; then
        echo "TSO: LRCPC v1 detected — partial hardware acceleration"
    else
        echo "TSO: Software memory barriers (reduced performance)"
    fi
fi

# ── Steam bootstrap ─────────────────────────────────────────────────
# Steam is an x86-64 application. On first run, we download the bootstrap
# package and extract it. Steam then self-updates into ~/.local/share/Steam/.

if [[ ! -f "${STEAM_DIR}/steam.sh" ]]; then
    echo ""
    echo "Steam is not installed. Bootstrapping..."
    echo ""

    mkdir -p "${STEAM_BOOTSTRAP_DIR}"
    STEAM_DEB="${STEAM_BOOTSTRAP_DIR}/steam.deb"

    # Download the Steam .deb bootstrap package
    if ! curl -fSL --progress-bar -o "${STEAM_DEB}" "${STEAM_BOOTSTRAP_URL}"; then
        echo "ERROR: Failed to download Steam bootstrap from ${STEAM_BOOTSTRAP_URL}"
        echo "Check your internet connection and try again."
        exit 1
    fi

    # Extract data.tar.xz from the .deb using python3 (ar/bsdtar not available
    # on immutable Fedora images, but python3 is always present)
    echo "Extracting Steam bootstrap..."
    python3 - "${STEAM_DEB}" "${STEAM_BOOTSTRAP_DIR}" << 'PYEXTRACT'
import struct, sys, os

deb_path = sys.argv[1]
out_dir = sys.argv[2]

with open(deb_path, 'rb') as f:
    magic = f.read(8)
    if magic != b'!<arch>\n':
        print("ERROR: Not a valid .deb archive", file=sys.stderr)
        sys.exit(1)
    while True:
        header = f.read(60)
        if len(header) < 60:
            break
        name = header[0:16].strip().decode()
        size = int(header[48:58].strip())
        data = f.read(size)
        if size % 2:
            f.read(1)
        if name.startswith('data.tar'):
            out_path = os.path.join(out_dir, name.rstrip('/'))
            with open(out_path, 'wb') as out:
                out.write(data)
            print(f"Extracted {name} ({size} bytes)")
            break
    else:
        print("ERROR: data.tar not found in .deb", file=sys.stderr)
        sys.exit(1)
PYEXTRACT

    # Find and extract the data tarball
    DATA_TAR=$(find "${STEAM_BOOTSTRAP_DIR}" -name 'data.tar.*' 2>/dev/null | head -1)
    if [[ -z "${DATA_TAR}" ]]; then
        echo "ERROR: Could not extract data archive from steam.deb"
        exit 1
    fi
    tar xf "${DATA_TAR}" -C "${STEAM_BOOTSTRAP_DIR}"

    # The bootstrap contains usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz
    BOOTSTRAP_TAR=$(find "${STEAM_BOOTSTRAP_DIR}" -name 'bootstraplinux_*.tar.xz' 2>/dev/null | head -1)
    if [[ -z "${BOOTSTRAP_TAR}" ]]; then
        echo "ERROR: Steam bootstrap tarball not found in .deb package"
        exit 1
    fi

    # Extract the bootstrap into Steam's install directory
    mkdir -p "${STEAM_DIR}"
    tar xf "${BOOTSTRAP_TAR}" -C "${STEAM_DIR}"

    # Clean up bootstrap files
    rm -rf "${STEAM_BOOTSTRAP_DIR}"

    echo ""
    echo "Steam bootstrap installed to ${STEAM_DIR}"
    echo "Launching Steam — it will update itself on first run..."
    echo ""
fi

# ── Launch Steam ────────────────────────────────────────────────────
exec FEXBash -c "${STEAM_DIR}/steam.sh $*"
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
