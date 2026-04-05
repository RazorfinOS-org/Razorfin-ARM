#!/usr/bin/env bash
# configure_iso.sh — Titanoboa post-rootfs hook for Razorfin-ARM ISOs
# Runs inside the rootfs chroot before it is squashed into squashfs.img.
# Adapted from x86 Razorfin's configure_iso.sh for aarch64 + COSMIC desktop.

set -exo pipefail

# shellcheck source=/dev/null
source /etc/os-release

###############################################################################
# Variables
###############################################################################
imageref="$(podman images --format '{{ index .Names 0 }}\n' 'razorfin-arm*' | head -1)"
imageref="${imageref##*://}"
imageref="${imageref%%:*}"
imagetag="$(podman images --format '{{ .Tag }}\n' "${imageref}" | head -1)"

###############################################################################
# Install Anaconda and dependencies
###############################################################################
dnf install -qy --allowerasing \
    anaconda-live \
    libblockdev-btrfs \
    libblockdev-lvm \
    libblockdev-dm

mkdir -p /var/lib/rpm-state

###############################################################################
# Disable unnecessary services in the live environment
###############################################################################
services_to_disable=(
    rpm-ostree-countme.timer
    tailscaled.service
    bootloader-cleanup.service
    brew-setup.service
    brew-upgrade.timer
    brew-update.timer
)

for svc in "${services_to_disable[@]}"; do
    systemctl disable "${svc}" 2>/dev/null || true
done

###############################################################################
# Configure COSMIC greeter/session for the live environment
###############################################################################
# Disable automatic sleep/suspend in the live environment so the installer
# does not get interrupted.
mkdir -p /etc/cosmic/com.system76.CosmicSettings.Power/v1
cat > /etc/cosmic/com.system76.CosmicSettings.Power/v1/0000-live-iso.ron <<'COSMIC_EOF'
(
    suspend_on_ac_timeout: None,
    suspend_on_battery_timeout: None,
    screen_off_on_ac_timeout: None,
    screen_off_on_battery_timeout: None,
    dim_on_ac_timeout: None,
    dim_on_battery_timeout: None,
)
COSMIC_EOF

###############################################################################
# Razorfin Anaconda profile
###############################################################################
mkdir -p /etc/anaconda/profile.d
cat > /etc/anaconda/profile.d/razorfin.conf <<'PROFILE_EOF'
# Anaconda configuration file for Razorfin-ARM

[Profile]
profile_id = razorfin

[Profile Detection]
os_id = razorfin

[Network]
default_on_boot = FIRST_WIRED_WITH_LINK

[Bootloader]
efi_dir = fedora
menu_auto_hide = True

[Storage]
default_scheme = BTRFS
btrfs_compression = zstd:1
default_partitioning =
    /     (min 1 GiB, max 70 GiB)
    /home (min 500 MiB, free 50 GiB)
    /var  (btrfs)

[User Interface]
custom_stylesheet = /usr/share/anaconda/pixmaps/fedora.css
hidden_spokes =
    NetworkSpoke
    PasswordSpoke

hidden_webui_pages =
    root-password
    network

[Localization]
use_geolocation = False
PROFILE_EOF

###############################################################################
# Branding
###############################################################################
echo "Razorfin-ARM release ${VERSION_ID}" > /etc/system-release

# Replace Fedora references in Anaconda
if [[ -f /usr/share/anaconda/pixmaps/fedora.css ]]; then
    sed -i 's/Fedora/Razorfin/g' /usr/share/anaconda/pixmaps/fedora.css
fi

###############################################################################
# Kickstart — post-install scripts
###############################################################################
cat >> /usr/share/anaconda/interactive-defaults.ks <<KICKSTART_EOF

# Deploy the container image from local containers-storage (embedded by Titanoboa)
ostreecontainer --url=${imageref}:${imagetag} --transport=containers-storage --no-signature-verification

# Razorfin-ARM post-install: bootc switch to the signed container image
%post --erroronfail
set -euo pipefail

imageref="${imageref}"
imagetag="${imagetag}"

# Switch to the target container image with signature verification
bootc switch --mutate-in-place --transport registry "\${imageref}:\${imagetag}"
%end
KICKSTART_EOF
