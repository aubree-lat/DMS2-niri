#!/usr/bin/env bash
# make the ps2 browser your default file manager and file picker, or undo it.
#
#   default-browser.sh enable
#   default-browser.sh disable
#   default-browser.sh picker-off   keep it as file manager, dialogs go back to kde/gtk
#   default-browser.sh picker-on    dialogs use it again
#
# enable does three things (each backed up first):
#   - folders open in ps2-browser (xdg-mime default for inode/directory)
#   - "show in folder" requests from apps go to it (org.freedesktop.FileManager1,
#     a d-bus activation file in ~/.local/share/dbus-1/services)
#   - file open/save dialogs use it (xdg-desktop-portal FileChooser, plus
#     GTK_USE_PORTAL/GDK_DEBUG in ~/.config/environment.d so gtk apps ask). this one
#     needs ps2browser.portal in /usr/share/xdg-desktop-portal/portals, which
#     takes sudo; the command is printed if it isn't there yet.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
config=${XDG_CONFIG_HOME:-$HOME/.config}
services=$data/dbus-1/services
state=$config/ps2-browser-defaults
desktop=${XDG_CURRENT_DESKTOP:-niri}
desktop=${desktop%%:*}
portals_conf=$config/xdg-desktop-portal/${desktop,,}-portals.conf
system_portal=/usr/share/xdg-desktop-portal/portals/ps2browser.portal
service_bin=$HOME/.local/bin/ps2-browser-service
# gtk apps outside flatpak only ask the portal for file dialogs when told to
gtk_env=$config/environment.d/96-ps2-file-picker.conf

backup() { [[ -e $1 && ! -e $1.ps2-original ]] && cp -a "$1" "$1.ps2-original" || true; }
restore() {
    if [[ -e $1.ps2-original ]]; then
        mv -f "$1.ps2-original" "$1"
    else
        rm -f "$1"
    fi
}

enable() {
    [[ -x $service_bin ]] || { echo "run ./install.sh first" >&2; exit 1; }
    mkdir -p "$services" "$(dirname "$portals_conf")"

    if [[ ! -f $state ]]; then
        echo "mime_dir=$(xdg-mime query default inode/directory 2>/dev/null || true)" > "$state"
    fi
    xdg-mime default ps2-browser.desktop inode/directory
    echo ":: folders open in ps2-browser"

    backup "$services/org.freedesktop.FileManager1.service"
    for name in org.freedesktop.FileManager1 org.freedesktop.impl.portal.desktop.ps2browser; do
        printf '[D-BUS Service]\nName=%s\nExec=%s\n' "$name" "$service_bin" > "$services/$name.service"
    done
    # take over from a file manager that already owns the name (it re-launches on demand)
    pkill -f '^/usr/bin/python3 -I [^ ]*/ps2-browser-servic[e]$' 2>/dev/null || true
    echo ":: show-in-folder requests go to ps2-browser"

    backup "$portals_conf"
    if [[ -f $portals_conf ]] && grep -q '^org.freedesktop.impl.portal.FileChooser=' "$portals_conf"; then
        sed -i 's/^org.freedesktop.impl.portal.FileChooser=.*/org.freedesktop.impl.portal.FileChooser=ps2browser;kde;gtk;/' "$portals_conf"
    elif [[ -f $portals_conf ]] && grep -q '^\[preferred\]' "$portals_conf"; then
        sed -i '/^\[preferred\]/a org.freedesktop.impl.portal.FileChooser=ps2browser;kde;gtk;' "$portals_conf"
    else
        printf '[preferred]\norg.freedesktop.impl.portal.FileChooser=ps2browser;kde;gtk;\n' >> "$portals_conf"
    fi
    mkdir -p "$(dirname "$gtk_env")"
    printf '# written by dms2-niri scripts/default-browser.sh\nGTK_USE_PORTAL=1\nGDK_DEBUG=portals\n' > "$gtk_env"
    systemctl --user set-environment GTK_USE_PORTAL=1 GDK_DEBUG=portals 2>/dev/null || true

    if [[ -f $system_portal ]]; then
        systemctl --user restart xdg-desktop-portal 2>/dev/null || true
        echo ":: file dialogs use ps2-browser (gtk apps after your next login)"
    else
        echo ":: file dialogs need one system file. run this, then log out and back in"
        echo "   (or: systemctl --user restart xdg-desktop-portal):"
        echo
        echo "   sudo install -Dm644 '$here/browser/ps2browser.portal' $system_portal"
        echo
    fi
}

disable() {
    if [[ -f $state ]]; then
        prev=$(sed -n 's/^mime_dir=//p' "$state")
        [[ -n $prev ]] && xdg-mime default "$prev" inode/directory
        rm -f "$state"
        echo ":: folders open in ${prev:-the system default} again"
    fi
    restore "$services/org.freedesktop.FileManager1.service"
    rm -f "$services/org.freedesktop.impl.portal.desktop.ps2browser.service"
    pkill -f '^/usr/bin/python3 -I [^ ]*/ps2-browser-servic[e]$' 2>/dev/null || true
    [[ -e $portals_conf.ps2-original || -e $portals_conf ]] && restore "$portals_conf"
    rm -f "$gtk_env"
    systemctl --user unset-environment GTK_USE_PORTAL GDK_DEBUG 2>/dev/null || true
    systemctl --user restart xdg-desktop-portal 2>/dev/null || true
    echo ":: file manager and file dialogs restored"
    if [[ -f $system_portal ]]; then
        echo "   the portal file can stay (it does nothing unless selected), or remove it:"
        echo "   sudo rm $system_portal"
    fi
}

picker_off() {
    if [[ -f $portals_conf ]]; then
        sed -i 's/^org.freedesktop.impl.portal.FileChooser=.*/org.freedesktop.impl.portal.FileChooser=kde;gtk;/' "$portals_conf"
    fi
    rm -f "$gtk_env"
    systemctl --user unset-environment GTK_USE_PORTAL GDK_DEBUG 2>/dev/null || true
    # values that came from environment.d at login only go away at the next login;
    # blank them meanwhile (gtk treats empty as off)
    dbus-update-activation-environment --systemd GTK_USE_PORTAL= GDK_DEBUG= 2>/dev/null || true
    systemctl --user restart xdg-desktop-portal 2>/dev/null || true
    echo ":: file dialogs back to kde (dolphin style), gtk apps use their own after your next login"
}

picker_on() {
    if [[ -f $portals_conf ]]; then
        sed -i 's/^org.freedesktop.impl.portal.FileChooser=.*/org.freedesktop.impl.portal.FileChooser=ps2browser;kde;gtk;/' "$portals_conf"
    fi
    mkdir -p "$(dirname "$gtk_env")"
    printf '# written by dms2-niri scripts/default-browser.sh\nGTK_USE_PORTAL=1\nGDK_DEBUG=portals\n' > "$gtk_env"
    systemctl --user set-environment GTK_USE_PORTAL=1 GDK_DEBUG=portals 2>/dev/null || true
    systemctl --user restart xdg-desktop-portal 2>/dev/null || true
    echo ":: file dialogs use ps2-browser"
}

case ${1:-} in
    enable) enable ;;
    disable) disable ;;
    picker-off) picker_off ;;
    picker-on) picker_on ;;
    *) echo "usage: $0 enable|disable|picker-off|picker-on" >&2; exit 1 ;;
esac
