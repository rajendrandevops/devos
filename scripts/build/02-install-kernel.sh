#!/bin/bash
# ============================================================
# DevOS Phase 2 — Kernel Installation
# Installs Debian Trixie kernel into the rootfs chroot
# ============================================================
set -euo pipefail

source /build/configs/devos.env

echo "=== DevOS Phase 2: Kernel Installation ==="
echo "    Kernel package : ${DEVOS_KERNEL_PACKAGE}"
echo "    Rootfs         : ${DEVOS_ROOTFS_DIR}"
echo ""

# Mount required virtual filesystems into chroot
echo "--- Mounting virtual filesystems ---"
mount --bind /proc "${DEVOS_ROOTFS_DIR}/proc"
mount --bind /sys  "${DEVOS_ROOTFS_DIR}/sys"
mount --bind /dev  "${DEVOS_ROOTFS_DIR}/dev"
mount --bind /dev/pts "${DEVOS_ROOTFS_DIR}/dev/pts"

# Ensure unmount happens even if script fails
cleanup() {
    echo "--- Unmounting virtual filesystems ---"
    # Check before unmounting — never use -l (lazy) which can remove host devices
    mountpoint -q "${DEVOS_ROOTFS_DIR}/dev/pts" && umount "${DEVOS_ROOTFS_DIR}/dev/pts" || true
    mountpoint -q "${DEVOS_ROOTFS_DIR}/dev"     && umount "${DEVOS_ROOTFS_DIR}/dev"     || true
    mountpoint -q "${DEVOS_ROOTFS_DIR}/sys"     && umount "${DEVOS_ROOTFS_DIR}/sys"     || true
    mountpoint -q "${DEVOS_ROOTFS_DIR}/proc"    && umount "${DEVOS_ROOTFS_DIR}/proc"    || true
    # Verify host /dev devices are intact
    [ -c /dev/null ]    || mknod -m 666 /dev/null    c 1 3
    [ -c /dev/urandom ] || mknod -m 666 /dev/urandom c 1 9
    [ -c /dev/random ]  || mknod -m 666 /dev/random  c 1 8
}
trap cleanup EXIT

# Prevent services starting during install
echo "--- Blocking service startup during install ---"
cat > "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d" << 'POLICY'
#!/bin/sh
exit 101
POLICY
chmod +x "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d"

# Update apt inside chroot
echo "--- Updating apt inside chroot ---"
chroot "${DEVOS_ROOTFS_DIR}" apt-get update -q

# Install kernel and headers
echo "--- Installing kernel: ${DEVOS_KERNEL_PACKAGE} ---"
chroot "${DEVOS_ROOTFS_DIR}" apt-get install -y \
    "${DEVOS_KERNEL_PACKAGE}" \
    "${DEVOS_KERNEL_HEADERS}" \
    initramfs-tools

# Remove policy blocker
rm -f "${DEVOS_ROOTFS_DIR}/usr/sbin/policy-rc.d"

echo ""
echo "=== Kernel installation complete ==="
echo ""
echo "--- Verifying kernel installation ---"
ERRORS=0

# Find installed kernel version
KVER=$(ls "${DEVOS_ROOTFS_DIR}/lib/modules/" 2>/dev/null | head -1)
if [ -z "$KVER" ]; then
    echo "  FAIL: No kernel modules found in /lib/modules/"
    ERRORS=$((ERRORS+1))
else
    echo "  PASS: Kernel version detected: ${KVER}"
fi

# Check kernel image
if ls "${DEVOS_ROOTFS_DIR}/boot/vmlinuz-"* 1>/dev/null 2>&1; then
    VMLINUZ=$(ls "${DEVOS_ROOTFS_DIR}/boot/vmlinuz-"* | head -1)
    echo "  PASS: Kernel image: $(basename ${VMLINUZ})"
else
    echo "  FAIL: No vmlinuz found in /boot/"
    ERRORS=$((ERRORS+1))
fi

# Check initramfs
if ls "${DEVOS_ROOTFS_DIR}/boot/initrd.img-"* 1>/dev/null 2>&1; then
    INITRD=$(ls "${DEVOS_ROOTFS_DIR}/boot/initrd.img-"* | head -1)
    echo "  PASS: Initramfs: $(basename ${INITRD})"
else
    echo "  FAIL: No initrd.img found in /boot/"
    ERRORS=$((ERRORS+1))
fi

# Check modules directory
if [ -d "${DEVOS_ROOTFS_DIR}/lib/modules/${KVER}" ]; then
    echo "  PASS: Modules directory: /lib/modules/${KVER}"
else
    echo "  FAIL: Modules directory missing"
    ERRORS=$((ERRORS+1))
fi

# Record kernel version
mkdir -p /build/kernel
echo "${KVER}" > /build/kernel/version-manifest.txt
echo "  INFO: Kernel version saved to /build/kernel/version-manifest.txt"

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== Phase 2 PASSED — kernel installed correctly ==="
    echo ""
    echo "    Kernel version : ${KVER}"
    echo "    Kernel image   : /boot/vmlinuz-${KVER}"
    echo "    Initramfs      : /boot/initrd.img-${KVER}"
    echo "    Modules        : /lib/modules/${KVER}"
else
    echo "=== Phase 2 FAILED — ${ERRORS} checks failed ==="
    exit 1
fi

echo ""
echo "--- Next step: Phase 3 — System Configuration ---"
