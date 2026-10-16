#!/usr/bin/env bash
# kvm-autofit installer - sudo ./install.sh [--uninstall] [--dry-run] [--no-lightdm]
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LIBEXEC=/usr/local/libexec/kvm-autofit
BIN=/usr/local/bin/kvm-autofit
DOC=/usr/local/share/doc/kvm-autofit
UDEV=/etc/udev/rules.d/90-kvm-autofit.rules
UNIT=/etc/systemd/system/kvm-autofit.service
LIGHTDM=/etc/lightdm/lightdm.conf.d/50-kvm-autofit.conf

DRY=0 UNINSTALL=0 WITH_LIGHTDM=1
for a in "$@"; do
    case $a in
        --dry-run)    DRY=1 ;;
        --uninstall)  UNINSTALL=1 ;;
        --no-lightdm) WITH_LIGHTDM=0 ;;
        -h|--help)    sed -n 2p "$0"; exit 0 ;;
        *)            echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

info() { printf '\033[32m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*" >&2; }
run()  { if (( DRY )); then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }

(( DRY || EUID == 0 )) || { echo "run with sudo: sudo $0 $*" >&2; exit 1; }

reload() {
    run udevadm control --reload
    run systemctl daemon-reload
}

if (( UNINSTALL )); then
    run rm -f "$UDEV" "$UNIT" "$LIGHTDM" "$BIN" "$LIBEXEC"
    run rm -rf "$DOC"
    reload
    info "kvm-autofit removed (LightDM picks the change up at next restart)"
    exit 0
fi

# --- guest checks (warn only: the tool is harmless outside KVM)
virt="$(systemd-detect-virt --vm 2>/dev/null || true)"
[[ $virt == kvm || $virt == qemu ]] || warn "not a KVM guest (detected: ${virt:-none}) - installing anyway"

# --- dependency: xrandr
if ! command -v xrandr >/dev/null; then
    if   command -v apt-get >/dev/null; then pkg=(apt-get install -y x11-xserver-utils)
    elif command -v dnf     >/dev/null; then pkg=(dnf install -y xrandr)
    elif command -v pacman  >/dev/null; then pkg=(pacman -S --needed --noconfirm xorg-xrandr)
    elif command -v zypper  >/dev/null; then pkg=(zypper -n install xrandr)
    else warn "install xrandr with your package manager, then re-run"; exit 1; fi
    info "installing xrandr: ${pkg[*]}"
    run "${pkg[@]}"
fi

# --- files
SYSTEMCTL="$(command -v systemctl)"
# The rust edition installs an enabled daemon under the same unit name: stop it first.
if systemctl is-enabled -q kvm-autofit.service 2>/dev/null; then
    info "disabling the rust edition daemon"
    run systemctl disable --now kvm-autofit.service
fi
info "installing $LIBEXEC"
run install -Dm755 "$ROOT/src/kvm-autofit" "$LIBEXEC"
run ln -sfn "$LIBEXEC" "$BIN"
[[ -f $ROOT/README.md ]] && run install -Dm644 "$ROOT/README.md" "$DOC/README.md"

info "installing udev rule $UDEV"
if (( DRY )); then
    printf '  [dry-run] render %s (systemctl=%s)\n' "$UDEV" "$SYSTEMCTL"
else
    sed "s|@SYSTEMCTL@|$SYSTEMCTL|" "$ROOT/dist/udev/90-kvm-autofit.rules" >"$UDEV"
    chmod 644 "$UDEV"
fi

info "installing systemd unit $UNIT"
run install -Dm644 "$ROOT/dist/systemd/kvm-autofit.service" "$UNIT"

if (( WITH_LIGHTDM )) && [[ -d /etc/lightdm ]]; then
    # Another display-setup/session-setup script would be silently overridden: refuse.
    other="$(grep -rlsE '^\s*(display|session)-setup-script' /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.d/ \
             | grep -v "$LIGHTDM" || true)"
    if [[ -n $other ]]; then
        warn "LightDM already defines a setup script in: $other"
        warn "skipping LightDM hooks - call '$LIBEXEC --display-setup' from that script instead"
    else
        info "installing LightDM hooks $LIGHTDM"
        run install -Dm644 "$ROOT/dist/lightdm/50-kvm-autofit.conf" "$LIGHTDM"
    fi
fi

reload
info "first fit"
run "$SYSTEMCTL" start kvm-autofit.service || warn "first fit failed - see: journalctl -t kvm-autofit -b"

cat <<EOF

done. Check with:   kvm-autofit doctor        (from a terminal inside the VM)
Logs:               journalctl -t kvm-autofit -b
LightDM hooks take effect at the next greeter (reboot or: sudo systemctl restart lightdm).
EOF
