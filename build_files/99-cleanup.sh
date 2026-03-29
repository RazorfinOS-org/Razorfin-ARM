#!/usr/bin/env bash
set -xeuo pipefail

# =============================================================================
# FINAL CLEANUP
# =============================================================================
# This is the last step in the build process. Regenerates initramfs,
# cleans caches, and removes build artifacts.

KERNEL_VERSION="$(rpm -q --queryformat='%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
if [[ -n "${KERNEL_VERSION}" ]]; then
    echo "Regenerating initramfs for kernel ${KERNEL_VERSION}..."

    # Ensure /root exists as a directory — dracut tries to install it into
    # the initramfs and fails in container builds where it may not exist.
    # It may exist as a file (symlink, etc.) so handle that case.
    if [[ ! -d /root ]]; then
        rm -f /root
        mkdir -p /root
    fi

    /usr/sbin/depmod -a "${KERNEL_VERSION}"

    export DRACUT_NO_XATTR=1
    /usr/bin/dracut --no-hostonly --kver "${KERNEL_VERSION}" --reproducible --add ostree -f "/lib/modules/${KERNEL_VERSION}/initramfs.img"
    chmod 0600 "/lib/modules/${KERNEL_VERSION}/initramfs.img"
fi

# Remove sb-key-notify autostart if present (inherited from ublue-setup-services)
rm -f /etc/profile.d/sbkey-notify-autostart.sh
rm -f /etc/skel/.config/autostart/sb-key-notify.desktop

dnf5 clean all

rm -rf /tmp/* /var/tmp/* || true
rm -rf /var/cache/dnf/* || true

# Clean up runtime artifacts that trigger bootc container lint warnings
rm -rf /run/dnf || true
rm -f /var/log/dnf5.log || true
