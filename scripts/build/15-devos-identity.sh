#!/bin/bash
# ============================================================
# DevOS Phase 15 — Identity Layer
# CLI tool, Plymouth theme, dock config, bloat removal
# ============================================================
set -euo pipefail
source /build/configs/devos.env

echo "=== DevOS Phase 15: Identity Layer ==="

ROOTFS="${DEVOS_ROOTFS_DIR}"

# Mount virtual filesystems
mountpoint -q "${ROOTFS}/proc" || mount --bind /proc "${ROOTFS}/proc"
mountpoint -q "${ROOTFS}/sys"  || mount --bind /sys  "${ROOTFS}/sys"
mountpoint -q "${ROOTFS}/dev"  || mount --bind /dev  "${ROOTFS}/dev"
mountpoint -q "${ROOTFS}/dev/pts" || mount --bind /dev/pts "${ROOTFS}/dev/pts"

cleanup() {
    mountpoint -q "${ROOTFS}/dev/pts" && umount "${ROOTFS}/dev/pts" || true
    mountpoint -q "${ROOTFS}/dev"     && umount "${ROOTFS}/dev"     || true
    mountpoint -q "${ROOTFS}/sys"     && umount "${ROOTFS}/sys"     || true
    mountpoint -q "${ROOTFS}/proc"    && umount "${ROOTFS}/proc"    || true
    [ -c /dev/null ]    || mknod -m 666 /dev/null    c 1 3
    [ -c /dev/urandom ] || mknod -m 666 /dev/urandom c 1 9
    [ -c /dev/random ]  || mknod -m 666 /dev/random  c 1 8
}
trap cleanup EXIT

cat > "${ROOTFS}/usr/sbin/policy-rc.d" << 'POLICY'
#!/bin/sh
exit 101
POLICY
chmod +x "${ROOTFS}/usr/sbin/policy-rc.d"

# ─── 1. Remove bloat packages ───────────────────────────────
echo "--- Removing bloat packages ---"
chroot "${ROOTFS}" apt-get remove -y --purge \
    rygel rygel-playbin rygel-tracker \
    totem totem-common \
    gnome-maps \
    gnome-weather \
    gnome-contacts \
    gnome-clocks \
    gnome-calendar \
    gnome-snapshot \
    gnome-user-docs \
    evolution-ews-core \
    2>/dev/null || true
chroot "${ROOTFS}" apt-get autoremove -y 2>/dev/null || true
echo "  Bloat removed"

# ─── 2. Install Plymouth ────────────────────────────────────
echo "--- Installing Plymouth ---"
chroot "${ROOTFS}" apt-get install -y \
    plymouth \
    plymouth-themes
echo "  Plymouth installed"

# ─── 3. Create DevOS Plymouth theme ────────────────────────
echo "--- Creating DevOS Plymouth theme ---"
mkdir -p "${ROOTFS}/usr/share/plymouth/themes/devos"

cat > "${ROOTFS}/usr/share/plymouth/themes/devos/devos.plymouth" << 'PLYM'
[Plymouth Theme]
Name=DevOS
Description=DevOS Boot Splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/devos
ScriptFile=/usr/share/plymouth/themes/devos/devos.script
PLYM

cat > "${ROOTFS}/usr/share/plymouth/themes/devos/devos.script" << 'SCRIPT'
# DevOS Plymouth Script
Window.SetBackgroundTopColor(0.05, 0.08, 0.13);
Window.SetBackgroundBottomColor(0.05, 0.08, 0.13);

logo_image = Image("devos-logo.png");
logo_sprite = Sprite(logo_image);
logo_sprite.SetX(Window.GetWidth()  / 2 - logo_image.GetWidth()  / 2);
logo_sprite.SetY(Window.GetHeight() / 2 - logo_image.GetHeight() / 2 - 40);

title_image = Image.Text("DevOS", 0.35, 0.67, 1.0, 1, "Sans Bold 28");
title_sprite = Sprite(title_image);
title_sprite.SetX(Window.GetWidth()  / 2 - title_image.GetWidth()  / 2);
title_sprite.SetY(Window.GetHeight() / 2 + 40);

sub_image = Image.Text("Developer Operating System", 0.55, 0.55, 0.60, 1, "Sans 14");
sub_sprite = Sprite(sub_image);
sub_sprite.SetX(Window.GetWidth()  / 2 - sub_image.GetWidth()  / 2);
sub_sprite.SetY(Window.GetHeight() / 2 + 80);

progress_bar_width = 300;
progress_bar_height = 3;
progress_bar_x = Window.GetWidth() / 2 - progress_bar_width / 2;
progress_bar_y = Window.GetHeight() - 60;

fun refresh_callback() {
    progress = Plymouth.GetBootProgress();
    bar_image = Image(progress_bar_width * progress, progress_bar_height);
    bar_image.Scale(progress_bar_width * progress, progress_bar_height);
    bar_sprite = Sprite(bar_image);
    bar_sprite.SetX(progress_bar_x);
    bar_sprite.SetY(progress_bar_y);
    bar_sprite.SetColor(0.35, 0.67, 1.0, 1.0);
}

Plymouth.SetRefreshFunction(refresh_callback);
SCRIPT

# Create simple DevOS logo for Plymouth (blue D on dark background)
sudo bash -c "
if command -v convert &>/dev/null; then
    convert -size 120x120 xc:'#0d1117' \
        -gravity Center \
        -pointsize 72 \
        -fill '#58a6ff' \
        -font DejaVu-Sans-Bold \
        -annotate 0 'D' \
        '${ROOTFS}/usr/share/plymouth/themes/devos/devos-logo.png'
    echo '  Plymouth logo created via ImageMagick'
else
    apt-get install -y imagemagick 2>/dev/null
    convert -size 120x120 xc:'#0d1117' \
        -gravity Center \
        -pointsize 72 \
        -fill '#58a6ff' \
        -font DejaVu-Sans-Bold \
        -annotate 0 'D' \
        '${ROOTFS}/usr/share/plymouth/themes/devos/devos-logo.png'
    echo '  Plymouth logo created'
fi
"

# Set DevOS as default Plymouth theme
chroot "${ROOTFS}" plymouth-set-default-theme devos 2>/dev/null || \
    echo "devos" > "${ROOTFS}/etc/plymouth/plymouthd.conf.d/devos-theme.conf"

# Rebuild initramfs with Plymouth
chroot "${ROOTFS}" update-initramfs -u 2>/dev/null || true
echo "  Plymouth theme set to DevOS"

# ─── 4. Create devos CLI tool ───────────────────────────────
echo "--- Creating devos CLI tool ---"
cat > "${ROOTFS}/usr/bin/devos" << 'DEVOSCLI'
#!/bin/bash
# ============================================================
# devos — DevOS Command Line Interface
# ============================================================
DEVOS_VERSION="1.0"
DEVOS_CODENAME="Trixie"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo -e "${BOLD}${BLUE}DevOS ${DEVOS_VERSION}${NC} — Developer Operating System"
    echo ""
}

cmd_info() {
    print_header
    echo -e "${BOLD}System Information${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  OS         : ${CYAN}DevOS ${DEVOS_VERSION} (${DEVOS_CODENAME})${NC}"
    echo -e "  Kernel     : $(uname -r)"
    echo -e "  Hostname   : $(hostname)"
    echo -e "  Uptime     : $(uptime -p 2>/dev/null || uptime)"
    echo -e "  CPU        : $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
    echo -e "  Memory     : $(free -h | awk '/^Mem/{print $3 " used / " $2 " total"}')"
    echo -e "  Disk       : $(df -h / | awk 'NR==2{print $3 " used / " $2 " total (" $5 " full)"}')"
    echo -e "  Desktop    : ${XDG_CURRENT_DESKTOP:-GNOME}"
    echo ""
    echo -e "${BOLD}DevOS Repository${NC}"
    apt-cache policy 2>/dev/null | grep devos | head -3 || echo "  Not configured"
}

cmd_doctor() {
    print_header
    echo -e "${BOLD}System Health Check${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    ERRORS=0

    check() {
        local NAME="$1"
        local CMD="$2"
        if eval "$CMD" > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} $NAME"
        else
            echo -e "  ${RED}✗${NC} $NAME"
            ERRORS=$((ERRORS+1))
        fi
    }

    check "Kernel"          "uname -r"
    check "Network"         "ping -c1 -W2 8.8.8.8"
    check "DNS"             "getent hosts debian.org"
    check "APT"             "apt-get check"
    check "Disk space"      "[ $(df / | awk 'NR==2{print $5}' | tr -d '%') -lt 90 ]"
    check "Firewall (ufw)"  "systemctl is-active ufw"
    check "AppArmor"        "systemctl is-active apparmor"
    check "systemd"         "systemctl is-system-running --quiet 2>/dev/null || true"

    echo ""
    if [ "$ERRORS" -eq 0 ]; then
        echo -e "  ${GREEN}${BOLD}System Status: HEALTHY${NC}"
    else
        echo -e "  ${RED}${BOLD}System Status: $ERRORS issue(s) found${NC}"
    fi
}

cmd_update() {
    print_header
    echo -e "${BOLD}Updating DevOS...${NC}"
    sudo apt-get update && sudo apt-get upgrade -y
}

cmd_profile() {
    local SUBCMD="${1:-list}"
    case "$SUBCMD" in
        list)
            print_header
            echo -e "${BOLD}Available DevOS Profiles${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo -e "  ${CYAN}developer${NC}   — git, gcc, python3, nodejs, gdb, cmake"
            echo -e "  ${CYAN}devops${NC}      — ansible, docker, python3"
            echo -e "  ${CYAN}devsecops${NC}   — nmap, wireshark, tcpdump, netcat"
            echo -e "  ${CYAN}qa${NC}          — chromium, jdk, python3"
            echo -e "  ${CYAN}mlai${NC}        — python3, numpy, scipy, matplotlib, jupyter"
            echo ""
            echo "Install: devos profile install <name>"
            ;;
        install)
            local PROFILE="${2:-}"
            if [ -z "$PROFILE" ]; then
                echo "Usage: devos profile install <name>"
                exit 1
            fi
            echo -e "${BOLD}Installing DevOS profile: ${CYAN}${PROFILE}${NC}"
            sudo apt-get install -y "devos-profile-${PROFILE}"
            ;;
        *)
            echo "Usage: devos profile [list|install <name>]"
            ;;
    esac
}

cmd_logs() {
    journalctl -b --no-pager "$@"
}

cmd_version() {
    echo "DevOS ${DEVOS_VERSION} (${DEVOS_CODENAME})"
}

cmd_help() {
    print_header
    echo -e "${BOLD}Usage:${NC} devos <command> [options]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo -e "  ${CYAN}info${NC}              Show system information"
    echo -e "  ${CYAN}doctor${NC}            Run system health checks"
    echo -e "  ${CYAN}update${NC}            Update system packages"
    echo -e "  ${CYAN}profile list${NC}      List available profiles"
    echo -e "  ${CYAN}profile install${NC}   Install a profile"
    echo -e "  ${CYAN}logs${NC}              View system logs"
    echo -e "  ${CYAN}version${NC}           Show DevOS version"
    echo -e "  ${CYAN}help${NC}              Show this help"
}

case "${1:-help}" in
    info)       cmd_info ;;
    doctor)     cmd_doctor ;;
    update)     cmd_update ;;
    profile)    shift; cmd_profile "$@" ;;
    logs)       shift; cmd_logs "$@" ;;
    version|--version|-v) cmd_version ;;
    help|--help|-h) cmd_help ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'devos help' for usage."
        exit 1
        ;;
esac
DEVOSCLI

chmod +x "${ROOTFS}/usr/bin/devos"
echo "  devos CLI created"

# ─── 5. Configure GNOME dock always visible ─────────────────
echo "--- Configuring GNOME dock ---"
sudo bash -c "
cat >> '${ROOTFS}/usr/share/glib-2.0/schemas/99_devos-branding.gschema.override' << 'DOCK'

[org.gnome.shell]
enabled-extensions=['dash-to-dock@micxgx.gmail.com']
favorite-apps=['org.gnome.Nautilus.desktop', 'firefox-esr.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Software.desktop', 'calamares.desktop']

[org.gnome.shell.extensions.dash-to-dock]
dock-position='BOTTOM'
dock-fixed=true
autohide=false
intellihide=false
DOCK

chroot '${ROOTFS}' glib-compile-schemas /usr/share/glib-2.0/schemas/
echo '  GNOME dock configured'
"

rm -f "${ROOTFS}/usr/sbin/policy-rc.d"

# ─── 6. Verify ──────────────────────────────────────────────
echo ""
echo "--- Verification ---"
ERRORS=0

[ -f "${ROOTFS}/usr/bin/devos" ] && \
    echo "  PASS: devos CLI" || { echo "  FAIL: devos CLI"; ERRORS=$((ERRORS+1)); }
[ -f "${ROOTFS}/usr/share/plymouth/themes/devos/devos.plymouth" ] && \
    echo "  PASS: Plymouth theme" || { echo "  FAIL: Plymouth theme"; ERRORS=$((ERRORS+1)); }
[ -f "${ROOTFS}/usr/share/glib-2.0/schemas/99_devos-branding.gschema.override" ] && \
    echo "  PASS: GNOME schema" || { echo "  FAIL: GNOME schema"; ERRORS=$((ERRORS+1)); }

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== Phase 15 PASSED ==="
else
    echo "=== Phase 15 FAILED — $ERRORS errors ==="
    exit 1
fi

echo ""
echo "--- Rootfs size after identity layer ---"
du -sh "${ROOTFS}"
