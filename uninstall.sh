#!/usr/bin/env bash
# dms2-niri uninstaller: restores your original settings and removes the files.
#
#   ./uninstall.sh                 revert and remove everything
#   ./uninstall.sh --keep-sounds   keep the sounds decoded from your bios
#
# the m plus rounded font is left installed (other apps may use it):
#   rm -r ~/.local/share/fonts/mplus-rounded
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
keep_sounds=0
[[ ${1:-} == --keep-sounds ]] && keep_sounds=1

data=${XDG_DATA_HOME:-$HOME/.local/share}
config=${XDG_CONFIG_HOME:-$HOME/.config}
dms_dir=${DMS_CONFIG_DIR:-$config/DankMaterialShell}

echo ":: restoring your original settings"
"$here/scripts/revert-look.sh"

echo ":: removing files"
rm -rf "$dms_dir/plugins/ps2Bios" "$dms_dir/themes/ps2Bios" \
    "$data/sounds/ps2-bios" \
    "$config/quickshell/ps2-intro" "$config/quickshell/ps2-browser" \
    "$HOME/.local/bin/ps2-browser" "$data/applications/ps2-browser.desktop"
(( keep_sounds )) || rm -rf "$data/ps2-bios-sounds"

# the backups have been restored; clear them so a later install starts fresh
rm -f "$dms_dir/settings.json.ps2-original" "$dms_dir/plugin_settings.json.ps2-original" \
    "$dms_dir/ps2-original-state" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/DankMaterialShell/session.json.ps2-original" \
    "$config/niri/config.kdl.ps2-original"

# --fetch replaced the active fastfetch config; put the previous one back
ff=$config/fastfetch
if [[ -f "$ff/config.jsonc.bak-ps2bios" ]]; then
    mv -f "$ff/config.jsonc.bak-ps2bios" "$ff/config.jsonc"
    echo ":: restored your fastfetch config"
fi
rm -rf "$ff/ps2bios"

dms restart >/dev/null 2>&1 || true
echo ":: done"
