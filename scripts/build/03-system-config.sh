#!/bin/bash
# ============================================================
# DevOS Phase 3 — System Configuration
# Configures locale, timezone, hostname, users, network, APT
# ============================================================
set -euo pipefail

source /build/configs/devos.env

echo "=== DevOS Phase 3: System Configuration ==="
echo "    Rootfs : ${DEVOS_ROOTFS_DIR}"
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

# Block services during config
cat > "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d" << 'POLICY'
#!/bin/sh
exit 101
POLICY
chmod +x "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d"

# --- 1. Hostname ---
echo "--- Setting hostname ---"
echo "devos" > "${DEVOS_ROOTFS_DIR}/etc/hostname"
cat > "${DEVOS_ROOTFS_DIR}/etc/hosts" << 'HOSTS'
127.0.0.1   localhost
127.0.1.1   devos
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTS
echo "  Done: hostname = devos"

# --- 2. Locale ---
echo "--- Configuring locale ---"
cat > "${DEVOS_ROOTFS_DIR}/etc/locale.gen" << 'LOCALE'
en_US.UTF-8 UTF-8
LOCALE
chroot "${DEVOS_ROOTFS_DIR}" locale-gen
cat > "${DEVOS_ROOTFS_DIR}/etc/locale.conf" << 'LCONF'
LANG=en_US.UTF-8
LCONF
echo "  Done: locale = en_US.UTF-8"

# --- 3. Timezone ---
echo "--- Setting timezone ---"
chroot "${DEVOS_ROOTFS_DIR}" ln -sf /usr/share/zoneinfo/UTC /etc/localtime
echo "UTC" > "${DEVOS_ROOTFS_DIR}/etc/timezone"
echo "  Done: timezone = UTC"

# --- 4. APT Sources ---
echo "--- Configuring APT sources ---"
cat > "${DEVOS_ROOTFS_DIR}/etc/apt/sources.list.d/debian.list" << 'SOURCES'
deb https://deb.debian.org/debian trixie main contrib non-free-firmware
deb https://security.debian.org/debian-security trixie-security main
deb https://deb.debian.org/debian trixie-updates main
SOURCES
# Remove old sources.list if present
rm -f "${DEVOS_ROOTFS_DIR}/etc/apt/sources.list"
echo "  Done: APT sources configured"

# --- 5. Network (NetworkManager) ---
echo "--- Configuring network ---"
chroot "${DEVOS_ROOTFS_DIR}" apt-get install -y -q \
    network-manager \
    ca-certificates
cat > "${DEVOS_ROOTFS_DIR}/etc/NetworkManager/NetworkManager.conf" << 'NM'
[main]
plugins=ifupdown,keyfile
dns=systemd-resolved

[ifupdown]
managed=true
NM
echo "  Done: NetworkManager configured"

# --- 6. Default user ---
echo "--- Creating default user: devos ---"
chroot "${DEVOS_ROOTFS_DIR}" useradd \
    --create-home \
    --shell /bin/bash \
    --groups sudo \
    --comment "DevOS User" \
    devos
# Set password: devos (will be changed on first login via Calamares)
echo "devos:devos" | chroot "${DEVOS_ROOTFS_DIR}" chpasswd
# Force password change on first login
chroot "${DEVOS_ROOTFS_DIR}" chage -d 0 devos
echo "  Done: user devos created (temporary password — Calamares will replace)"

# --- 7. Sudo configuration ---
echo "--- Configuring sudo ---"
cat > "${DEVOS_ROOTFS_DIR}/etc/sudoers.d/devos" << 'SUDO'
devos ALL=(ALL:ALL) ALL
SUDO
chmod 440 "${DEVOS_ROOTFS_DIR}/etc/sudoers.d/devos"
echo "  Done: sudo configured"

# Remove policy blocker
rm -f "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d"

# --- Verification ---
echo ""
echo "--- Verifying system configuration ---"
ERRORS=0

check_file() {
    [ -f "${DEVOS_ROOTFS_DIR}/$1" ] \
        && echo "  PASS: $1" \
        || { echo "  FAIL: $1 missing"; ERRORS=$((ERRORS+1)); }
}

check_contains() {
    grep -q "$2" "${DEVOS_ROOTFS_DIR}/$1" \
        && echo "  PASS: $1 contains '$2'" \
        || { echo "  FAIL: $1 missing '$2'"; ERRORS=$((ERRORS+1)); }
}

check_file "etc/hostname"
check_file "etc/hosts"
check_file "etc/locale.conf"
check_file "etc/timezone"
check_file "etc/apt/sources.list.d/debian.list"
check_contains "etc/hostname" "devos"
check_contains "etc/locale.conf" "en_US.UTF-8"
check_contains "etc/timezone" "UTC"
check_contains "etc/apt/sources.list.d/debian.list" "trixie-security"

# Check user exists
chroot "${DEVOS_ROOTFS_DIR}" id devos > /dev/null 2>&1 \
    && echo "  PASS: user devos exists" \
    || { echo "  FAIL: user devos not found"; ERRORS=$((ERRORS+1)); }

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== Phase 3 PASSED — system configured correctly ==="
else
    echo "=== Phase 3 FAILED — ${ERRORS} checks failed ==="
    exit 1
fi

echo ""
echo "--- Next step: Phase 4 — GNOME Desktop Installation ---"
