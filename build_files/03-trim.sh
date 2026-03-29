#!/usr/bin/env bash
set -xeuo pipefail

# =============================================================================
# TRIM FEDORA COSMIC ATOMIC DEFAULTS
# =============================================================================
# Remove packages from the Fedora COSMIC Atomic base that are not needed
# for a gaming-focused ARM desktop. Be conservative — only remove packages
# that are clearly unnecessary and won't break COSMIC or its dependencies.
#
# To audit the base image:
#   podman run --rm quay.io/fedora-ostree-desktops/cosmic-atomic:43 rpm -qa | sort

# Remove LibreOffice if present (users can install via Flatpak)
dnf5 remove -y libreoffice* 2>/dev/null || true

# Remove GNOME apps that may have been pulled in as dependencies
dnf5 remove -y \
    gnome-calculator \
    gnome-text-editor \
    gnome-clocks \
    gnome-weather \
    gnome-contacts \
    gnome-maps \
    gnome-characters \
    totem \
    cheese \
    rhythmbox \
    2>/dev/null || true

# Remove Fedora branding that conflicts with Razorfin
dnf5 remove -y \
    fedora-bookmarks \
    fedora-chromium-config \
    2>/dev/null || true

# Autoremove orphaned dependencies
dnf5 autoremove -y 2>/dev/null || true

# Audit remaining packages
echo "=== Package count after trim ==="
rpm -qa | wc -l
echo "=== Largest 20 packages ==="
rpm -qa --queryformat '%{SIZE} %{NAME}\n' | sort -rn | head -20 || true
