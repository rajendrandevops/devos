#!/bin/bash
# ============================================================
# DevOS Phase 6 — Live ISO Build
# ============================================================
set -euo pipefail
source /build/configs/devos.env

echo "=== DevOS Phase 6: Live ISO Build ==="
echo "    Output: ${DEVOS_OUTPUT_DIR}/devos-1.0-amd64.iso"
echo ""

# Get kernel version
KVER=$(ls "${DEVOS_ROOTFS_DIR}/boot/vmlinuz-"* | head -1 | sed 's|.*/vmlinuz-||')
echo "--- Kernel version: ${KVER} ---"

# Prepare ISO tree
echo "--- Preparing ISO tree ---"
mkdir -p "${DEVOS_ISO_TREE}/live"
mkdir -p "${DEVOS_ISO_TREE}/boot/grub"
mkdir -p "${DEVOS_ISO_TREE}/EFI/boot"

# Copy kernel and initramfs
echo "--- Copying kernel and initramfs ---"
cp "${DEVOS_ROOTFS_DIR}/boot/vmlinuz-${KVER}" "${DEVOS_ISO_TREE}/live/vmlinuz"
cp "${DEVOS_ROOTFS_DIR}/boot/initrd.img-${KVER}" "${DEVOS_ISO_TREE}/live/initrd.img"
echo "  vmlinuz: $(du -sh ${DEVOS_ISO_TREE}/live/vmlinuz | cut -f1)"
echo "  initrd : $(du -sh ${DEVOS_ISO_TREE}/live/initrd.img | cut -f1)"

# Build SquashFS
echo "--- Building SquashFS (this takes 10-20 minutes) ---"
mksquashfs \
    "${DEVOS_ROOTFS_DIR}" \
    "${DEVOS_ISO_TREE}/live/filesystem.squashfs" \
    -comp xz \
    -Xbcj x86 \
    -b 1M \
    -no-progress \
    -noappend \
    -e boot
echo "  SquashFS: $(du -sh ${DEVOS_ISO_TREE}/live/filesystem.squashfs | cut -f1)"

# Write GRUB config
echo "--- Writing GRUB configuration ---"
cat > "${DEVOS_ISO_TREE}/boot/grub/grub.cfg" << 'GRUBCFG'
set default=0
set timeout=5

menuentry "DevOS 1.0 — Live Session" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}

menuentry "DevOS 1.0 — Live Session (safe graphics)" {
    linux /live/vmlinuz boot=live components nomodeset
    initrd /live/initrd.img
}

menuentry "DevOS 1.0 — Live Session (debug)" {
    linux /live/vmlinuz boot=live components
    initrd /live/initrd.img
}
GRUBCFG

# Build ISO
echo "--- Building ISO with xorriso ---"
mkdir -p "${DEVOS_OUTPUT_DIR}"
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "${DEVOS_ISO_LABEL}" \
    -output "${DEVOS_OUTPUT_DIR}/devos-1.0-amd64.iso" \
    -eltorito-boot boot/grub/i386-pc/eltorito.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --eltorito-catalog boot/grub/boot.cat \
    --grub2-boot-info \
    --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
    -eltorito-alt-boot \
    -e EFI/efiboot.img \
    -no-emul-boot \
    -append_partition 2 0xef "${DEVOS_ISO_TREE}/EFI/efiboot.img" \
    -m "${DEVOS_ISO_TREE}/EFI/efiboot.img" \
    -m "${DEVOS_ISO_TREE}/boot/grub/i386-pc/eltorito.img" \
    "${DEVOS_ISO_TREE}"

echo ""
echo "=== ISO build complete ==="
echo "--- Output ---"
ls -lh "${DEVOS_OUTPUT_DIR}/devos-1.0-amd64.iso"
sha256sum "${DEVOS_OUTPUT_DIR}/devos-1.0-amd64.iso" | tee "${DEVOS_OUTPUT_DIR}/devos-1.0-amd64.iso.sha256"
