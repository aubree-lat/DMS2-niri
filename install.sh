#!/usr/bin/env bash
# dms2-niri installer. per-user, no sudo.
#
#   ./install.sh               install, then ask before changing your settings
#   ./install.sh -y            answer yes to everything
#   ./install.sh --no-look     only install files, don't touch dms/niri settings
#   ./install.sh --bios FILE   decode sounds from this ps2 bios dump
#   ./install.sh --no-bios     skip the bios sound step
#   ./install.sh --fetch       also write the fetch and fastfetch configs
#   ./install.sh --no-default  don't offer to make ps2-browser the default file manager
#
# undo everything with ./uninstall.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
yes=0 look=1 bios="" use_bios=1 fetch=0 default=1
while (( $# )); do
    case $1 in
        -y | --yes) yes=1 ;;
        --no-look) look=0 ;;
        --bios) bios=${2:?--bios needs a file}; shift ;;
        --no-bios) use_bios=0 ;;
        --fetch) fetch=1 ;;
        --no-default) default=0 ;;
        -h | --help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
    esac
    shift
done

say() { printf '\n%s\n' "$*"; }
ask() {
    (( yes )) && return 0
    local reply
    read -r -p "$1 [Y/n] " reply || return 1
    [[ -z $reply || $reply == [yY]* ]]
}

# ---- dependencies ----
say "checking dependencies"
missing=()
for cmd in dms qs python3 ffmpeg jq rsync git curl fc-cache; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if (( ${#missing[@]} )); then
    echo "missing: ${missing[*]}"
    echo "install those first (dms = dankmaterialshell, qs = quickshell)"
    exit 1
fi
command -v niri >/dev/null || echo "note: niri not found. the boot animation and backdrop tweaks need niri"
command -v qsb >/dev/null || [[ -x /usr/lib/qt6/bin/qsb ]] || echo "note: qsb (qt6-shadertools) not found, using the prebuilt shaders"
command -v wl-copy >/dev/null || echo "note: wl-copy not found, 'copy path' in the file browser won't work"
have_numpy=1
python3 -I -c 'import numpy, scipy' 2>/dev/null || have_numpy=0

# ---- font ----
if ! fc-list : family 2>/dev/null | grep -i 'rounded mplus 1c' >/dev/null; then
    say "installing font: m plus rounded 1c (google fonts, ofl)"
    fontdir=${XDG_DATA_HOME:-$HOME/.local/share}/fonts/mplus-rounded
    mkdir -p "$fontdir"
    for w in Light Regular Medium Bold; do
        curl -fsSL -o "$fontdir/MPLUSRounded1c-$w.ttf" \
            "https://github.com/google/fonts/raw/main/ofl/mplusrounded1c/MPLUSRounded1c-$w.ttf"
    done
    fc-cache -f "$fontdir" >/dev/null
fi

# ---- sounds from your own bios (optional) ----
if (( use_bios )); then
    if [[ -z $bios ]]; then
        for pcsx2 in "$HOME/.var/app/net.pcsx2.PCSX2/config/PCSX2" "${XDG_CONFIG_HOME:-$HOME/.config}/PCSX2"; do
            name=$(sed -n 's/^BIOS = //p' "$pcsx2/inis/PCSX2.ini" 2>/dev/null | head -1)
            if [[ -n $name && -f "$pcsx2/bios/$name" ]]; then
                bios=$pcsx2/bios/$name
                break
            fi
        done
    fi
    if [[ -n $bios ]]; then
        if (( ! have_numpy )); then
            say "found a bios but python numpy/scipy are missing, skipping the bios sounds"
        elif ask "decode the real cursor tick and boot jingle from your bios ($(basename "$bios"))?"; then
            say "decoding bios sounds (takes about half a minute)"
            "$here/scripts/extract-bios-sounds.sh" "$bios" >/dev/null
            echo "done: ${XDG_DATA_HOME:-$HOME/.local/share}/ps2-bios-sounds"
        fi
    else
        say "no ps2 bios found, using the sound pack only (--bios FILE to decode one)"
    fi
fi

# ---- files ----
say "installing files"
"$here/scripts/install-files.sh"

# ---- look ----
if (( look )); then
    say "the look changes your dms theme, font, corners, animations, blur, bar,"
    echo "lock screen widgets, wallpaper and sound theme, and adds two tagged lines"
    echo "to ~/.config/niri/config.kdl. originals are backed up, ./uninstall.sh restores them."
    if ask "apply it now?"; then
        "$here/scripts/apply-look.sh"
        say "restarting dms"
        dms restart >/dev/null 2>&1 || true
    else
        echo "skipped. run ./scripts/apply-look.sh later"
    fi
fi

# ---- default file manager + file picker ----
if (( default )); then
    say "ps2-browser can be your default file manager and the file picker apps open"
    echo "(folders, 'show in folder', and open/save dialogs through xdg-desktop-portal)."
    if ask "make it the default?"; then
        "$here/scripts/default-browser.sh" enable
    else
        echo "skipped. run ./scripts/default-browser.sh enable later"
    fi
fi

# ---- fetch configs (optional) ----
if (( fetch )); then
    say "writing fetch and fastfetch configs"
    python3 -I "$here/fetch/build.py" --activate
fi

say "all done"
echo "file browser: ps2-browser (or 'ps2 browser' in the launcher)"
echo "boot animation: plays on your next login. replay: dms ipc call ps2bios intro"
echo "settings: dms settings > plugins > ps2 bios"
