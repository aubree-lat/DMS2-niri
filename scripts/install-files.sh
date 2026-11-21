#!/usr/bin/env bash
# copies the mod into place (per-user, no sudo). normally run by ../install.sh.
#   plugin            -> ~/.config/DankMaterialShell/plugins/ps2Bios
#   theme             -> ~/.config/DankMaterialShell/themes/ps2Bios
#   xdg sound theme   -> ~/.local/share/sounds/ps2-bios
#   boot sequence     -> ~/.config/quickshell/ps2-intro (spawned by niri)
#   file browser      -> ~/.config/quickshell/ps2-browser + ~/.local/bin/ps2-browser
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
dms_dir=${DMS_CONFIG_DIR:-$HOME/.config/DankMaterialShell}
plugin_dst=$dms_dir/plugins/ps2Bios
theme_dst=$dms_dir/themes/ps2Bios
sound_dst=${XDG_DATA_HOME:-$HOME/.local/share}/sounds/ps2-bios
qsb=$(command -v qsb || echo /usr/lib/qt6/bin/qsb)

echo ":: plugin -> $plugin_dst"
mkdir -p "$plugin_dst" "$theme_dst"
rsync -a --delete --exclude sounds/ "$here/plugin/ps2Bios/" "$plugin_dst/"

if [[ -x "$qsb" ]]; then
    "$qsb" --glsl "100 es,120,150" --hlsl 50 --msl 12 \
        -o "$plugin_dst/shaders/ps2clock.frag.qsb" "$plugin_dst/shaders/ps2clock.frag"
else
    echo "   qsb not found (qt6-shadertools), using the prebuilt shader"
fi

if [[ -f "$plugin_dst/sounds/navigate.wav" && -f "$sound_dst/index.theme" && -z "${PS2_REFRESH_SOUNDS:-}" ]]; then
    echo ":: sounds already built (PS2_REFRESH_SOUNDS=1 to rebuild)"
else
    echo ":: sounds (fetching junomede/ps2-system-sounds)"
    "$here/scripts/build-sounds.sh" "$plugin_dst/sounds" "$sound_dst" "${PS2_SOUNDS_SRC:-}"
fi

# Real BIOS sounds, when scripts/extract-bios-sounds.sh has been run: the decoded
# cursor tick for menu navigation, the edge bump for errors and the boot jingle
# for startup, level-matched to the pack sounds they replace.
bios_rendered=${XDG_DATA_HOME:-$HOME/.local/share}/ps2-bios-sounds/rendered
if [[ -f "$bios_rendered/cursor-tick.wav" && -z "${PS2_PACK_ONLY:-}" ]]; then
    echo ":: using decoded bios cursor tick, edge bump and boot jingle (PS2_PACK_ONLY=1 to skip)"
    for pair in navigate:cursor-tick error:edge-bump boot:boot-jingle; do
        cue=${pair%%:*} src=${pair#*:}
        [[ -f "$plugin_dst/sounds/$cue.pack.wav" ]] || cp "$plugin_dst/sounds/$cue.wav" "$plugin_dst/sounds/$cue.pack.wav"
        python3 -I "$here/tools/match_level.py" "$bios_rendered/$src.wav" "$plugin_dst/sounds/$cue.pack.wav" "$plugin_dst/sounds/$cue.wav" >/dev/null
    done
else
    for cue in navigate error boot; do
        if [[ -f "$plugin_dst/sounds/$cue.pack.wav" ]]; then
            cp "$plugin_dst/sounds/$cue.pack.wav" "$plugin_dst/sounds/$cue.wav"
        fi
    done
fi

intro_dst=${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ps2-intro
echo ":: standalone boot sequence -> $intro_dst"
mkdir -p "$intro_dst"
cp -f "$here/intro/shell.qml" "$plugin_dst/Ps2Intro.qml" "$intro_dst/"
rsync -a --delete "$plugin_dst/shaders/" "$intro_dst/shaders/"
ln -sfn "$plugin_dst/sounds" "$intro_dst/sounds"

browser_dst=${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ps2-browser
echo ":: file browser -> $browser_dst (+ ~/.local/bin/ps2-browser, desktop entry)"
mkdir -p "$browser_dst"
rm -rf "$browser_dst/shaders"
cp -f "$here"/browser/{shell.qml,Tile.qml,GlassDialog.qml,OrbGyro.qml,Icons.js} "$browser_dst/"
ln -sfn "$plugin_dst/sounds" "$browser_dst/sounds"
install -Dm755 "$here/browser/ps2-browser" "$HOME/.local/bin/ps2-browser"
install -Dm755 "$here/browser/ps2-browser-service" "$HOME/.local/bin/ps2-browser-service"
install -Dm644 "$here/browser/ps2-browser.desktop" "${XDG_DATA_HOME:-$HOME/.local/share}/applications/ps2-browser.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications" 2>/dev/null || true

echo ":: theme -> $theme_dst"
rsync -a "$here/theme/ps2Bios/" "$theme_dst/"

echo ":: files installed"
