#!/bin/bash
# ============================================================
# DevOS Phase 12 — Developer Profile Metapackages
# ============================================================
set -euo pipefail
source /build/configs/devos.env

echo "=== DevOS Phase 12: Developer Profile Metapackages ==="

PKGDIR="/build/packages"
mkdir -p "$PKGDIR"

create_metapkg() {
    local NAME="$1"
    local VERSION="$2"
    local DESC="$3"
    local DEPS="$4"

    mkdir -p "$PKGDIR/$NAME/DEBIAN"
    cat > "$PKGDIR/$NAME/DEBIAN/control" << CTRL
Package: $NAME
Version: $VERSION
Architecture: all
Maintainer: DevOS Project <devos-archive@devos.example>
Description: $DESC
Section: metapackages
Priority: optional
Depends: $DEPS
CTRL

    dpkg-deb --build "$PKGDIR/$NAME" \
        "$PKGDIR/${NAME}_${VERSION}_all.deb"
    echo "  Built: ${NAME}_${VERSION}_all.deb"
}

echo "--- Creating developer profile metapackages ---"

# Developer profile
create_metapkg "devos-profile-developer" "1.0" \
    "DevOS Developer Profile — core development tools" \
    "git, gcc, g++, make, cmake, ninja-build, \
python3, python3-pip, python3-venv, \
nodejs, npm, gdb, valgrind, strace, \
build-essential, pkg-config, curl, wget"

# DevOps profile
create_metapkg "devos-profile-devops" "1.0" \
    "DevOS DevOps Profile — infrastructure and automation tools" \
    "git, curl, wget, \
ansible, \
docker.io, \
python3, python3-pip"

# DevSecOps profile
create_metapkg "devos-profile-devsecops" "1.0" \
    "DevOS DevSecOps Profile — security tools" \
    "git, curl, nmap, \
wireshark, \
python3, python3-pip, \
netcat-openbsd, tcpdump"

# QA profile
create_metapkg "devos-profile-qa" "1.0" \
    "DevOS QA Profile — testing and quality assurance tools" \
    "git, curl, wget, \
python3, python3-pip, \
chromium, \
default-jdk"

# ML/AI profile
create_metapkg "devos-profile-mlai" "1.0" \
    "DevOS ML/AI Profile — machine learning and AI tools" \
    "python3, python3-pip, python3-venv, \
python3-numpy, python3-scipy, \
python3-matplotlib, \
jupyter, \
git, curl"

echo ""
echo "--- Adding packages to DevOS repository ---"
export GNUPGHOME=/root/.gnupg
for DEB in "$PKGDIR"/devos-profile-*.deb; do
    echo "  Adding: $(basename $DEB)"
    reprepro -b /srv/devos-repo includedeb trixie "$DEB"
done

echo ""
echo "--- Repository contents ---"
reprepro -b /srv/devos-repo list trixie

echo ""
echo "=== Phase 12 COMPLETE ==="
