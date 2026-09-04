#!/bin/bash
# ============================================================
# DevOS Phase 1 — Minimal Root Filesystem
# Builds a minimal Debian Trixie base using mmdebstrap
# ============================================================
set -euo pipefail

# Load single source of truth
source /build/configs/devos.env

echo "=== DevOS Phase 1: Root Filesystem Build ==="
echo "    Base     : ${DEVOS_BASE_CODENAME}"
echo "    Mirror   : ${DEVOS_BASE_MIRROR}"
echo "    Output   : ${DEVOS_ROOTFS_DIR}"
echo "    Variant  : ${DEVOS_BASE_VARIANT}"
echo ""

# Verify output directory exists and is empty
if [ -d "${DEVOS_ROOTFS_DIR}" ] && [ "$(ls -A ${DEVOS_ROOTFS_DIR})" ]; then
    echo "ERROR: ${DEVOS_ROOTFS_DIR} is not empty."
    echo "       Run: sudo rm -rf ${DEVOS_ROOTFS_DIR}/* to clean it first."
    exit 1
fi

mkdir -p "${DEVOS_ROOTFS_DIR}"

echo "--- Starting mmdebstrap ---"
echo "    This will take 5-15 minutes depending on network speed."
echo ""

sudo mmdebstrap \
    --variant="${DEVOS_BASE_VARIANT}" \
    --arch="${DEVOS_ARCH}" \
    --components="main,contrib,non-free,non-free-firmware" \
    --include="systemd,systemd-sysv,dbus,udev,apt,apt-utils,\
locales,tzdata,keyboard-configuration,console-setup,\
iproute2,iputils-ping,curl,wget,ca-certificates,\
bash-completion,man-db,less,vim,nano,\
sudo,adduser,passwd" \
    "${DEVOS_BASE_CODENAME}" \
    "${DEVOS_ROOTFS_DIR}" \
    "${DEVOS_BASE_MIRROR}"

echo ""
echo "=== mmdebstrap complete ==="
echo ""
echo "--- Verifying rootfs ---"

# Basic sanity checks
ERRORS=0

check() {
    if [ -e "${DEVOS_ROOTFS_DIR}/$1" ]; then
        echo "  PASS: $1"
    else
        echo "  FAIL: $1 missing"
        ERRORS=$((ERRORS+1))
    fi
}

check "bin"
check "etc"
check "lib"
check "usr"
check "var"
check "proc"
check "sys"
check "dev"
check "run"
check "tmp"
check "etc/apt/sources.list.d"
check "usr/bin/bash"
check "usr/bin/apt"
check "lib/systemd/systemd"
check "usr/sbin/init"

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== Phase 1 PASSED — rootfs looks healthy ==="
else
    echo "=== Phase 1 FAILED — $ERRORS checks failed ==="
    exit 1
fi

echo ""
echo "--- Rootfs size ---"
du -sh "${DEVOS_ROOTFS_DIR}"
echo ""
echo "--- Next step: Phase 2 — Kernel installation ---"
