#!/usr/bin/env bash
# Puts DMS back the way it was before the first apply-look.sh run.
# The ps2Bios plugin, theme and sound theme stay installed (just unused).
set -euo pipefail

dms_dir=${DMS_CONFIG_DIR:-$HOME/.config/DankMaterialShell}
state=$dms_dir/ps2-original-state

session=${XDG_STATE_HOME:-$HOME/.local/state}/DankMaterialShell/session.json
if [[ -f "$session.ps2-original" ]]; then
    systemctl --user stop dms 2>/dev/null || true
    cp -a "$session.ps2-original" "$session"
    systemctl --user start dms 2>/dev/null || true
    echo "restored session.json"
fi

for f in settings.json plugin_settings.json; do
    if [[ -f "$dms_dir/$f.ps2-original" ]]; then
        cp -a "$dms_dir/$f.ps2-original" "$dms_dir/$f"
        echo "restored $f"
    fi
done

if [[ -f "$state" ]]; then
    wallpaper=$(sed -n 's/^wallpaper=//p' "$state")
    sound_theme=$(sed -n 's/^sound_theme=//p' "$state")
    [[ -n "$wallpaper" ]] && dms ipc call wallpaper set "$wallpaper" >/dev/null && echo "wallpaper -> $wallpaper"
    [[ -n "$sound_theme" ]] && gsettings set org.gnome.desktop.sound theme-name "$sound_theme" && echo "sound theme -> $sound_theme"
fi

niri_cfg=${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl
if [[ -f "$niri_cfg" ]] && grep -q 'ps2Bios' "$niri_cfg"; then
    sed -i -e '/\/\/ ps2Bios/d' -e '/ps2Bios boot sequence/d' "$niri_cfg"
    echo "removed the ps2Bios lines from niri config.kdl"
fi

dms ipc call plugins disable ps2Bios >/dev/null 2>&1 || true
echo "reverted (run dms restart if window corners don't update)"
