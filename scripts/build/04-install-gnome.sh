#!/bin/bash
# ============================================================
# DevOS Phase 4 — GNOME Desktop Installation
# Installs GNOME 48 desktop environment into the rootfs
# ============================================================
set -euo pipefail

source /build/configs/devos.env

echo "=== DevOS Phase 4: GNOME Desktop Installation ==="
echo "    Desktop : ${DEVOS_DESKTOP}"
echo "    Rootfs  : ${DEVOS_ROOTFS_DIR}"
echo ""

# Mount virtual filesystems
echo "--- Mounting virtual filesystems ---"
mountpoint -q "${DEVOS_ROOTFS_DIR}/proc" || mount --bind /proc "${DEVOS_ROOTFS_DIR}/proc"
mountpoint -q "${DEVOS_ROOTFS_DIR}/sys"  || mount --bind /sys  "${DEVOS_ROOTFS_DIR}/sys"
mountpoint -q "${DEVOS_ROOTFS_DIR}/dev"  || mount --bind /dev  "${DEVOS_ROOTFS_DIR}/dev"
mountpoint -q "${DEVOS_ROOTFS_DIR}/dev/pts" || mount --bind /dev/pts "${DEVOS_ROOTFS_DIR}/dev/pts"

cleanup() {
    echo "--- Unmounting virtual filesystems ---"
    mountpoint -q "${DEVOS_ROOTFS_DIR}/dev/pts" && umount "${DEVOS_ROOTFS_DIR}/dev/pts" || true
    mountpoint -q "${DEVOS_ROOTFS_DIR}/dev"     && umount "${DEVOS_ROOTFS_DIR}/dev"     || true
    mountpoint -q "${DEVOS_ROOTFS_DIR}/sys"     && umount "${DEVOS_ROOTFS_DIR}/sys"     || true
    mountpoint -q "${DEVOS_ROOTFS_DIR}/proc"    && umount "${DEVOS_ROOTFS_DIR}/proc"    || true
    [ -c /dev/null ]    || mknod -m 666 /dev/null    c 1 3
    [ -c /dev/urandom ] || mknod -m 666 /dev/urandom c 1 9
    [ -c /dev/random ]  || mknod -m 666 /dev/random  c 1 8
}
trap cleanup EXIT

# Block services during install
cat > "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d" << 'POLICY'
#!/bin/sh
exit 101
POLICY
chmod +x "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d"

# Set noninteractive to suppress prompts
export DEBIAN_FRONTEND=noninteractive

echo "--- Updating apt ---"
chroot "${DEVOS_ROOTFS_DIR}" apt-get update -q

echo "--- Installing GNOME desktop (this will take 20-40 minutes) ---"
chroot "${DEVOS_ROOTFS_DIR}" apt-get install -y \
    gnome-core \
    gdm3 \
    gnome-terminal \
    gnome-text-editor \
    nautilus \
    gnome-control-center \
    gnome-system-monitor \
    gnome-disk-utility \
    gnome-software \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    pipewire \
    pipewire-pulse \
    wireplumber \
    fonts-dejavu \
    fonts-liberation \
    firefox-esr \
    xdg-utils \
    xdg-user-dirs-gtk

# Remove policy blocker
rm -f "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d"

echo ""
echo "=== GNOME installation complete ==="
echo ""
echo "--- Verifying GNOME installation ---"
ERRORS=0

check() {
    [ -e "${DEVOS_ROOTFS_DIR}/$1" ] \
        && echo "  PASS: $1" \
        || { echo "  FAIL: $1 missing"; ERRORS=$((ERRORS+1)); }
}

check "usr/bin/gnome-shell"
check "usr/sbin/gdm3"
check "usr/bin/nautilus"
check "usr/bin/gnome-terminal"
check "usr/lib/systemd/system/gdm.service"
check "usr/lib/systemd/user/pipewire.service"
check "usr/bin/firefox-esr"

# Check GDM is set as default display manager
if [ -f "${DEVOS_ROOTFS_DIR}/etc/X11/default-display-manager" ]; then
    DM=$(cat "${DEVOS_ROOTFS_DIR}/etc/X11/default-display-manager")
    echo "  INFO: Default display manager: ${DM}"
fi

# Enable GDM in systemd
chroot "${DEVOS_ROOTFS_DIR}" systemctl set-default graphical.target 2>/dev/null || true

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== Phase 4 PASSED — GNOME desktop installed ==="
else
    echo "=== Phase 4 FAILED — ${ERRORS} checks failed ==="
    exit 1
fi

echo ""
echo "--- Rootfs size after GNOME ---"
du -sh "${DEVOS_ROOTFS_DIR}"
echo ""
echo "--- Next step: Phase 5 — Branding ==="
