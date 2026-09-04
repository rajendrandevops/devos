#!/bin/bash
# ============================================================
# DevOS Phase 8 — Security Hardening
# ============================================================
set -euo pipefail
source /build/configs/devos.env

echo "=== DevOS Phase 8: Security Hardening ==="

# Mount virtual filesystems
mountpoint -q "${DEVOS_ROOTFS_DIR}/proc" || mount --bind /proc "${DEVOS_ROOTFS_DIR}/proc"
mountpoint -q "${DEVOS_ROOTFS_DIR}/sys"  || mount --bind /sys  "${DEVOS_ROOTFS_DIR}/sys"
mountpoint -q "${DEVOS_ROOTFS_DIR}/dev"  || mount --bind /dev  "${DEVOS_ROOTFS_DIR}/dev"
mountpoint -q "${DEVOS_ROOTFS_DIR}/dev/pts" || mount --bind /dev/pts "${DEVOS_ROOTFS_DIR}/dev/pts"

cleanup() {
    mountpoint -q "${DEVOS_ROOTFS_DIR}/dev/pts" && umount "${DEVOS_ROOTFS_DIR}/dev/pts" || true
    mountpoint -q "${DEVOS_ROOTFS_DIR}/dev"     && umount "${DEVOS_ROOTFS_DIR}/dev"     || true
    mountpoint -q "${DEVOS_ROOTFS_DIR}/sys"     && umount "${DEVOS_ROOTFS_DIR}/sys"     || true
    mountpoint -q "${DEVOS_ROOTFS_DIR}/proc"    && umount "${DEVOS_ROOTFS_DIR}/proc"    || true
    [ -c /dev/null ]    || mknod -m 666 /dev/null    c 1 3
    [ -c /dev/urandom ] || mknod -m 666 /dev/urandom c 1 9
    [ -c /dev/random ]  || mknod -m 666 /dev/random  c 1 8
}
trap cleanup EXIT

cat > "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d" << 'POLICY'
#!/bin/sh
exit 101
POLICY
chmod +x "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d"

# --- 1. Install ufw ---
echo "--- Installing ufw ---"
chroot "${DEVOS_ROOTFS_DIR}" apt-get install -y -q ufw

# --- 2. Configure ufw ---
echo "--- Configuring ufw ---"
# Enable ufw with default deny incoming, allow outgoing
chroot "${DEVOS_ROOTFS_DIR}" ufw --force reset
chroot "${DEVOS_ROOTFS_DIR}" ufw default deny incoming
chroot "${DEVOS_ROOTFS_DIR}" ufw default allow outgoing
# Enable ufw at boot
chroot "${DEVOS_ROOTFS_DIR}" systemctl enable ufw
echo "  Done: ufw configured — default deny incoming"

# --- 3. AppArmor enforce mode ---
echo "--- Configuring AppArmor ---"
# Ensure AppArmor is enabled at boot with enforce mode
cat > "${DEVOS_ROOTFS_DIR}/etc/default/grub.d/apparmor.cfg" << 'AACONF'
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=1 security=apparmor"
AACONF
# AppArmor systemd already linked — verify
ls "${DEVOS_ROOTFS_DIR}/etc/systemd/system/sysinit.target.wants/apparmor.service" \
    && echo "  Done: AppArmor systemd service enabled" \
    || echo "  WARN: AppArmor systemd symlink missing"

# --- 4. APT security configuration ---
echo "--- Configuring APT security ---"
cat > "${DEVOS_ROOTFS_DIR}/etc/apt/apt.conf.d/99devos-security" << 'APTCONF'
// DevOS APT Security Configuration
// Never allow unauthenticated packages
APT::Get::AllowUnauthenticated "false";
APT::Get::AllowInsecureRepositories "false";
Acquire::AllowInsecureRepositories "false";
Acquire::AllowDowngradeToInsecureRepositories "false";
APTCONF
echo "  Done: APT GPG enforcement configured"

# --- 5. Kernel hardening via sysctl ---
echo "--- Configuring kernel hardening (sysctl) ---"
cat > "${DEVOS_ROOTFS_DIR}/etc/sysctl.d/99-devos-hardening.conf" << 'SYSCTL'
# DevOS Kernel Hardening
# Network hardening
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv6.conf.all.accept_redirects = 0
# Kernel hardening
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 1
kernel.yama.ptrace_scope = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
SYSCTL
echo "  Done: kernel hardening sysctl configured"

# --- 6. Disable root login ---
echo "--- Securing root account ---"
chroot "${DEVOS_ROOTFS_DIR}" passwd -l root
echo "  Done: root account locked"

rm -f "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d"

# --- Verification ---
echo ""
echo "--- Verifying security configuration ---"
ERRORS=0

check_file() {
    [ -f "${DEVOS_ROOTFS_DIR}/$1" ] \
        && echo "  PASS: $1" \
        || { echo "  FAIL: $1 missing"; ERRORS=$((ERRORS+1)); }
}

check_file "usr/sbin/ufw"
check_file "etc/apt/apt.conf.d/99devos-security"
check_file "etc/sysctl.d/99-devos-hardening.conf"
check_file "etc/systemd/system/sysinit.target.wants/apparmor.service"

# Verify APT config
grep -q 'AllowUnauthenticated "false"' "${DEVOS_ROOTFS_DIR}/etc/apt/apt.conf.d/99devos-security" \
    && echo "  PASS: APT authentication enforced" \
    || { echo "  FAIL: APT auth config wrong"; ERRORS=$((ERRORS+1)); }

# Verify root is locked
chroot "${DEVOS_ROOTFS_DIR}" passwd -S root | grep -q ' L ' \
    && echo "  PASS: root account locked" \
    || { echo "  FAIL: root not locked"; ERRORS=$((ERRORS+1)); }

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== Phase 8 PASSED — security hardening complete ==="
else
    echo "=== Phase 8 FAILED — ${ERRORS} checks failed ==="
    exit 1
fi

echo ""
echo "--- SUID audit ---"
find "${DEVOS_ROOTFS_DIR}" -perm -4000 -type f 2>/dev/null \
    | sed "s|${DEVOS_ROOTFS_DIR}||" | sort

echo ""
echo "--- Next step: Phase 9 — DevOS Repository ==="
