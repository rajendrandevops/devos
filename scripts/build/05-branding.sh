#!/bin/bash
# ============================================================
# DevOS Phase 5 — Branding
# Sets DevOS identity: os-release, wallpaper, motd, issue
# ============================================================
set -euo pipefail
source /build/configs/devos.env

echo "=== DevOS Phase 5: Branding ==="

sudo mkdir -p "${DEVOS_ROOTFS_DIR}/usr/share/devos/wallpapers"
sudo mkdir -p "${DEVOS_ROOTFS_DIR}/usr/share/devos/logo"
sudo mkdir -p "${DEVOS_ROOTFS_DIR}/usr/share/plymouth/themes/devos"

sudo tee "${DEVOS_ROOTFS_DIR}/etc/os-release" > /dev/null << 'OSREL'
PRETTY_NAME="DevOS 1.0 (Trixie)"
NAME="DevOS"
VERSION_ID="1.0"
VERSION="1.0 (Trixie)"
VERSION_CODENAME=trixie
ID=devos
ID_LIKE=debian
HOME_URL="https://github.com/rajendrandevops/devos"
SUPPORT_URL="https://github.com/rajendrandevops/devos/issues"
BUG_REPORT_URL="https://github.com/rajendrandevops/devos/issues"
OSREL

sudo tee "${DEVOS_ROOTFS_DIR}/etc/issue" > /dev/null << 'ISSUE'
DevOS 1.0 \n \l
ISSUE

echo "=== Phase 5 PASSED — branding applied ==="
