#!/usr/bin/env bash
set -xeuo pipefail

# =============================================================================
# DEVELOPER EXPERIENCE (DX) TOOLS
# =============================================================================
# Only installed when DX_VARIANT=true. Provides a comprehensive developer
# toolchain for the Razorfin-ARM DX variant.

DX_VARIANT="${DX_VARIANT:-false}"

if [[ "${DX_VARIANT}" != "true" ]]; then
    echo "DX_VARIANT is not true, skipping developer tools installation"
    exit 0
fi

echo "Installing Razorfin-ARM DX developer tools..."

# Build essentials
dnf5 install -y \
    gcc \
    gcc-c++ \
    make \
    cmake \
    meson \
    ninja-build \
    autoconf \
    automake \
    pkg-config

# Rust toolchain
dnf5 install -y \
    rust \
    cargo

# Python and Node.js
dnf5 install -y \
    python3-devel \
    python3-pip \
    nodejs \
    npm

# Container and distrobox tools
dnf5 install -y \
    podman-compose \
    buildah \
    skopeo \
    distrobox

# Debugging and profiling
dnf5 install -y \
    strace \
    ltrace \
    gdb \
    valgrind \
    perf

# Editors and utilities
dnf5 install -y \
    vim-enhanced \
    ripgrep \
    fd-find \
    jq

echo "DX developer tools installation complete."
