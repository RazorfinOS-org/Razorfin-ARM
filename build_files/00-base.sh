#!/usr/bin/env bash
set -xeuo pipefail

# =============================================================================
# OS-RELEASE BRANDING
# =============================================================================
# Customize os-release for Razorfin branding (shown in GRUB via PRETTY_NAME)

VERSION_ID=$(grep "^VERSION_ID=" /usr/lib/os-release | cut -d'=' -f2)
OSTREE_VERSION="${VERSION_ID}.$(TZ=America/New_York date +%Y%m%d).0"

# Add OSTREE_VERSION if not present, otherwise update it
if grep -q "^OSTREE_VERSION=" /usr/lib/os-release; then
    sed -i "s/^OSTREE_VERSION=.*/OSTREE_VERSION='${OSTREE_VERSION}'/" /usr/lib/os-release
else
    echo "OSTREE_VERSION='${OSTREE_VERSION}'" >> /usr/lib/os-release
fi

sed -i 's/^NAME=.*/NAME="Razorfin"/' /usr/lib/os-release
sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"Razorfin (Version: ${OSTREE_VERSION})\"/" /usr/lib/os-release
sed -i 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="razorfin"/' /usr/lib/os-release
sed -i 's|^HOME_URL=.*|HOME_URL="https://github.com/RazorfinOS-org/Razorfin-ARM"|' /usr/lib/os-release
sed -i 's|^DOCUMENTATION_URL=.*|DOCUMENTATION_URL="https://github.com/RazorfinOS-org/Razorfin-ARM"|' /usr/lib/os-release
sed -i 's|^SUPPORT_URL=.*|SUPPORT_URL="https://github.com/RazorfinOS-org/Razorfin-ARM/issues"|' /usr/lib/os-release
sed -i 's|^BUG_REPORT_URL=.*|BUG_REPORT_URL="https://github.com/RazorfinOS-org/Razorfin-ARM/issues"|' /usr/lib/os-release

sed -i 's/^ID=.*/ID=razorfin/' /usr/lib/os-release
sed -i "s/^VERSION=.*/VERSION=\"${VERSION_ID} (Cosmonaut)\"/" /usr/lib/os-release
sed -i 's/^VERSION_CODENAME=.*/VERSION_CODENAME="Cosmonaut"/' /usr/lib/os-release
sed -i 's/^LOGO=.*/LOGO=razorfin/' /usr/lib/os-release
sed -i 's/^VARIANT=.*/VARIANT="COSMIC"/' /usr/lib/os-release
sed -i 's/^VARIANT_ID=.*/VARIANT_ID=razorfin/' /usr/lib/os-release
sed -i 's|^CPE_NAME=.*|CPE_NAME=cpe:/o:razorfinos-org:razorfin:'"${VERSION_ID}"'|' /usr/lib/os-release

# Add IMAGE_ID if not present
if grep -q "^IMAGE_ID=" /usr/lib/os-release; then
    sed -i 's/^IMAGE_ID=.*/IMAGE_ID=razorfin-arm/' /usr/lib/os-release
else
    echo "IMAGE_ID=razorfin-arm" >> /usr/lib/os-release
fi

# Add BOOTLOADER_NAME if not present
if grep -q "^BOOTLOADER_NAME=" /usr/lib/os-release; then
    sed -i "s/^BOOTLOADER_NAME=.*/BOOTLOADER_NAME=\"Razorfin (${OSTREE_VERSION})\"/" /usr/lib/os-release
else
    echo "BOOTLOADER_NAME=\"Razorfin (${OSTREE_VERSION})\"" >> /usr/lib/os-release
fi

# =============================================================================
# PACKAGES
# =============================================================================

dnf5 install -y \
    zsh \
    tmux \
    htop \
    git \
    curl \
    wget \
    jq \
    fastfetch \
    distrobox \
    wl-clipboard \
    fira-code-fonts \
    google-noto-sans-fonts

# =============================================================================
# PLYMOUTH BOOT SPLASH BRANDING
# =============================================================================

cp -r /ctx/build/plymouth/razorfin /usr/share/plymouth/themes/

# Replace spinner's watermark with Razorfin logo
cp /ctx/build/plymouth/razorfin/watermark.png /usr/share/plymouth/themes/spinner/watermark.png

plymouth-set-default-theme razorfin

systemctl enable podman.socket

# =============================================================================
# RAZORFIN BRANDING (MOTD & FASTFETCH)
# =============================================================================

mkdir -p /usr/share/ublue-os/razorfin
cp /ctx/build/razorfin/logo.txt /usr/share/ublue-os/razorfin/
cp /ctx/build/razorfin/fastfetch.jsonc /usr/share/ublue-os/razorfin/

# Install razorfin-fetch-image helper script
cp /ctx/build/razorfin/razorfin-fetch-image /usr/libexec/
chmod +x /usr/libexec/razorfin-fetch-image

# Install fastfetch aliases
cp /ctx/build/razorfin/razorfin-neofetch.sh /etc/profile.d/zzz-razorfin-neofetch.sh

# Install MOTD and tips
mkdir -p /usr/share/ublue-os/motd/tips
cp /ctx/build/razorfin/motd.md /usr/share/ublue-os/motd/razorfin.md
cp /ctx/build/razorfin/tips.md /usr/share/ublue-os/motd/tips/10-razorfin.md

# Create image-info.json for branding
mkdir -p /usr/share/ublue-os
cat > /usr/share/ublue-os/image-info.json << 'IMAGEINFO'
{
  "image-name": "razorfin-arm",
  "image-vendor": "RazorfinOS",
  "image-branch": "latest"
}
IMAGEINFO

# Install our own MOTD script since ublue-motd is not available on Fedora COSMIC Atomic
cat > /usr/libexec/razorfin-motd << 'MOTDSCRIPT'
#!/usr/bin/bash
# Razorfin MOTD — displayed on interactive login

MOTD_FILE="/usr/share/ublue-os/motd/razorfin.md"
TIPS_DIR="/usr/share/ublue-os/motd/tips"
IMAGE_INFO="/usr/share/ublue-os/image-info.json"

if [[ ! -f "${MOTD_FILE}" ]]; then
    exit 0
fi

# Read image info
IMAGE_NAME="razorfin-arm"
IMAGE_BRANCH="latest"
if [[ -f "${IMAGE_INFO}" ]]; then
    IMAGE_NAME=$(jq -r '.["image-name"] // "razorfin-arm"' < "${IMAGE_INFO}" 2>/dev/null || echo "razorfin-arm")
    IMAGE_BRANCH=$(jq -r '.["image-branch"] // "latest"' < "${IMAGE_INFO}" 2>/dev/null || echo "latest")
fi

# Pick a random tip
TIP=""
if [[ -d "${TIPS_DIR}" ]]; then
    TIPS_FILE=$(find "${TIPS_DIR}" -name "*.md" -type f | head -1)
    if [[ -n "${TIPS_FILE}" ]]; then
        TOTAL=$(grep -c '~' "${TIPS_FILE}" 2>/dev/null || echo 0)
        if [[ "${TOTAL}" -gt 0 ]]; then
            LINE=$((RANDOM % TOTAL + 1))
            RAW=$(sed -n "${LINE}p" "${TIPS_FILE}" 2>/dev/null)
            TIP_TEXT="${RAW%%~*}"
            TIP_LINK="${RAW#*~}"
            TIP="**Tip:** ${TIP_TEXT}"
            if [[ -n "${TIP_LINK}" && "${TIP_LINK}" != "${TIP_TEXT}" ]]; then
                TIP="${TIP} ${TIP_LINK}"
            fi
        fi
    fi
fi

# Greenboot status
GREENBOOT="System is healthy"

# Render MOTD
sed -e "s|%IMAGE_NAME%|${IMAGE_NAME}|g" \
    -e "s|%IMAGE_BRANCH%|${IMAGE_BRANCH}|g" \
    -e "s|%GREENBOOT%|${GREENBOOT}|g" \
    -e "s|%TIP%|${TIP}|g" \
    "${MOTD_FILE}"
MOTDSCRIPT
chmod +x /usr/libexec/razorfin-motd

# Add MOTD to login profile
cat > /etc/profile.d/zzz-razorfin-motd.sh << 'MOTDPROFILE'
# Display Razorfin MOTD on interactive login
if [[ -x /usr/libexec/razorfin-motd ]] && [[ -t 0 ]]; then
    /usr/libexec/razorfin-motd
fi
MOTDPROFILE

# =============================================================================
# SYSUSERS WORKAROUND FOR CONTAINER BUILDS
# =============================================================================
# In Fedora 42+, rpm-ostree/bootc container builds don't process sysusers.d files.
# Fedora COSMIC Atomic should already have these users, but we verify and create
# them if missing (which can happen in container builds).

# --- cosmic-greeter user (UID/GID 950) ---
COSMIC_GREETER_UID=950
COSMIC_GREETER_GID=950

if ! grep -q "^cosmic-greeter:" /usr/lib/passwd 2>/dev/null; then
    echo "cosmic-greeter:x:${COSMIC_GREETER_UID}:${COSMIC_GREETER_GID}:COSMIC Greeter:/var/lib/cosmic-greeter:/sbin/nologin" >> /usr/lib/passwd
fi
if ! grep -q "^cosmic-greeter:" /usr/lib/group 2>/dev/null; then
    echo "cosmic-greeter:x:${COSMIC_GREETER_GID}:" >> /usr/lib/group
fi

# --- greetd user (UID/GID 951) ---
GREETD_UID=951
GREETD_GID=951

if ! grep -q "^greetd:" /usr/lib/passwd 2>/dev/null; then
    echo "greetd:x:${GREETD_UID}:${GREETD_GID}:greetd daemon:/var/lib/greetd:/sbin/nologin" >> /usr/lib/passwd
fi
if ! grep -q "^greetd:" /usr/lib/group 2>/dev/null; then
    echo "greetd:x:${GREETD_GID}:" >> /usr/lib/group
fi

# --- abrt user (UID 173) ---
ABRT_UID=173
ABRT_GID=173

if ! grep -q "^abrt:" /usr/lib/passwd 2>/dev/null; then
    echo "abrt:x:${ABRT_UID}:${ABRT_GID}::/etc/abrt:/sbin/nologin" >> /usr/lib/passwd
fi
if ! grep -q "^abrt:" /usr/lib/group 2>/dev/null; then
    echo "abrt:x:${ABRT_GID}:" >> /usr/lib/group
fi

# Mirror system users into /etc/passwd and /etc/group for NSS resolution.
# bootc container lint runs systemd-tmpfiles which resolves users via NSS,
# but in the container build context nss-altfiles/nss-systemd can't reach
# /usr/lib/passwd. Entries in /etc/passwd are always resolvable.
for user_entry in \
    "cosmic-greeter:x:${COSMIC_GREETER_UID}:${COSMIC_GREETER_GID}:COSMIC Greeter:/var/lib/cosmic-greeter:/sbin/nologin" \
    "greetd:x:${GREETD_UID}:${GREETD_GID}:greetd daemon:/var/lib/greetd:/sbin/nologin" \
    "abrt:x:${ABRT_UID}:${ABRT_GID}::/etc/abrt:/sbin/nologin"; do
    username="${user_entry%%:*}"
    if ! grep -q "^${username}:" /etc/passwd 2>/dev/null; then
        echo "${user_entry}" >> /etc/passwd
    fi
done
for group_entry in \
    "cosmic-greeter:x:${COSMIC_GREETER_GID}:" \
    "greetd:x:${GREETD_GID}:" \
    "abrt:x:${ABRT_GID}:"; do
    groupname="${group_entry%%:*}"
    if ! grep -q "^${groupname}:" /etc/group 2>/dev/null; then
        echo "${group_entry}" >> /etc/group
    fi
done

# Add cosmic-greeter to video and render groups for GPU access
for group in video render; do
    for gfile in /usr/lib/group /etc/group; do
        if grep -q "^${group}:" "${gfile}"; then
            if ! grep -q "^${group}:.*cosmic-greeter" "${gfile}"; then
                sed -i "s/^\(${group}:.*\)$/\1,cosmic-greeter/" "${gfile}"
            fi
        fi
    done
done

# Clean up malformed group entries
sed -i 's/:,/:/g; s/,,/,/g' /usr/lib/group

# Create home directories
mkdir -p /var/lib/cosmic-greeter/.config/cosmic
mkdir -p /var/lib/cosmic-greeter/.local/state/cosmic-comp
chown -R ${COSMIC_GREETER_UID}:${COSMIC_GREETER_GID} /var/lib/cosmic-greeter
chmod 750 /var/lib/cosmic-greeter

mkdir -p /var/lib/greetd
chown -R ${GREETD_UID}:${GREETD_GID} /var/lib/greetd
chmod 750 /var/lib/greetd

# =============================================================================
# DEFAULT USER ACCOUNT
# =============================================================================
# Create a default user for first boot. Users should change the password
# after first login. The account has sudo access via the wheel group.

DEFAULT_USER="razorfin"
DEFAULT_PASS="razorfin"

# Create user in both /usr/lib/passwd and /etc/passwd
# UID 1000 is the standard first-user ID
if ! grep -q "^${DEFAULT_USER}:" /usr/lib/passwd 2>/dev/null; then
    echo "${DEFAULT_USER}:x:1000:1000:Razorfin User:/var/home/${DEFAULT_USER}:/usr/bin/zsh" >> /usr/lib/passwd
fi
if ! grep -q "^${DEFAULT_USER}:" /etc/passwd 2>/dev/null; then
    echo "${DEFAULT_USER}:x:1000:1000:Razorfin User:/var/home/${DEFAULT_USER}:/usr/bin/zsh" >> /etc/passwd
fi
if ! grep -q "^${DEFAULT_USER}:" /usr/lib/group 2>/dev/null; then
    echo "${DEFAULT_USER}:x:1000:" >> /usr/lib/group
fi
if ! grep -q "^${DEFAULT_USER}:" /etc/group 2>/dev/null; then
    echo "${DEFAULT_USER}:x:1000:" >> /etc/group
fi

# Add user to wheel group for sudo access
for gfile in /usr/lib/group /etc/group; do
    if grep -q "^wheel:" "${gfile}"; then
        if ! grep -q "^wheel:.*${DEFAULT_USER}" "${gfile}"; then
            sed -i "s/^\(wheel:.*\)$/\1,${DEFAULT_USER}/" "${gfile}"
            sed -i 's/:,/:/g; s/,,/,/g' "${gfile}"
        fi
    fi
done

# Set password using chpasswd
echo "${DEFAULT_USER}:${DEFAULT_PASS}" | chpasswd

# Also unlock root with the same password for emergency console access
echo "root:${DEFAULT_PASS}" | chpasswd

# Set zsh as default shell for root too
sed -i 's|^root:\(.*\):/bin/bash|root:\1:/usr/bin/zsh|' /etc/passwd
sed -i 's|^root:\(.*\):/bin/bash|root:\1:/usr/bin/zsh|' /usr/lib/passwd

# Create home directory with default zsh config
mkdir -p /var/home/${DEFAULT_USER}

cat > /var/home/${DEFAULT_USER}/.zshrc << 'ZSHRC'
# Razorfin default zsh configuration
autoload -Uz compinit && compinit
autoload -Uz promptinit && promptinit

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory sharehistory hist_ignore_dups

# Key bindings
bindkey -e

# Prompt
PS1='%F{cyan}%n%f@%F{green}%m%f %F{blue}%~%f %# '

# Aliases
alias ls='ls --color=auto'
alias ll='ls -lah'
alias grep='grep --color=auto'
ZSHRC

# Also install as default skel for new users
mkdir -p /etc/skel
cp /var/home/${DEFAULT_USER}/.zshrc /etc/skel/.zshrc

chown -R 1000:1000 /var/home/${DEFAULT_USER}
chmod 700 /var/home/${DEFAULT_USER}

# Disable services that commonly fail in VM/container environments
systemctl disable auditd.service 2>/dev/null || true
systemctl mask rpc-gssd.service 2>/dev/null || true
systemctl mask rpcbind.service 2>/dev/null || true
systemctl mask rpcbind.socket 2>/dev/null || true

systemctl set-default graphical.target
