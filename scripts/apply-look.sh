#!/usr/bin/env bash
# Switches a running DMS over to the PS2 BIOS look. DMS watches settings.json
# and reloads it, so no restart is needed for most of this.
#
# The pre-PS2 state is saved once, on the first run, as <file>.ps2-original
# plus ps2-original-state (wallpaper, sound theme); scripts/revert-look.sh
# puts it back.
set -euo pipefail

dms_dir=${DMS_CONFIG_DIR:-$HOME/.config/DankMaterialShell}
settings=$dms_dir/settings.json
plugin_settings=$dms_dir/plugin_settings.json

[[ -d "$dms_dir/plugins/ps2Bios" ]] || { echo "run ./install.sh first" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

for f in "$settings" "$plugin_settings"; do
    [[ -f "$f" && ! -f "$f.ps2-original" ]] && cp -a "$f" "$f.ps2-original"
done
state=$dms_dir/ps2-original-state
if [[ ! -f "$state" ]]; then
    {
        echo "wallpaper=$(dms ipc call wallpaper get 2>/dev/null)"
        echo "sound_theme=$(gsettings get org.gnome.desktop.sound theme-name 2>/dev/null | tr -d "'")"
    } > "$state"
fi
echo ":: original settings saved as *.ps2-original (+ $state)"

write_json() {
    local file=$1 filter=$2 tmp
    tmp=$(mktemp "$file.XXXX")
    jq "$filter" "$file" > "$tmp"
    mv "$tmp" "$file"
}

# Plugin on, with defaults that sit well under the PS2 sounds.
[[ -f "$plugin_settings" ]] || echo '{}' > "$plugin_settings"
write_json "$plugin_settings" '.ps2Bios = ((.ps2Bios // {}) + {enabled: true})'

theme_file="$dms_dir/themes/ps2Bios/theme.json"
write_json "$settings" '
  def scene(id; extra):
    {id: id, widgetType: "ps2Bios", name: "PS2 BIOS", enabled: true,
     config: ({displayPreferences: ["all"], syncPositionAcrossScreens: false} + extra)};

  .currentThemeName = "custom"
  | .customThemeFile = "'"$theme_file"'"
  | .soundsEnabled = true
  | .useSystemSoundTheme = true
  # The plugin boot sequence plays the login cue itself.
  | .soundLogin = false
  | .soundNewNotification = true
  | .soundVolumeChanged = true
  | .soundPluggedIn = true
  | .lockScreenFontFamily = "Rounded Mplus 1c"
  # Faceted crystal, not pills: tight corners everywhere (niri windows follow this too).
  | .radiusStrength = 8
  # Finish-the-look pass (2026-11-21). Keybinds are never touched.
  # Classic style: no shape-morphing or pill controls, crisp like the menu panels.
  | .interfaceStyle = "classic"
  | .radiusMode = "fixed" | .fixedRadius = 4
  | .fontFamily = "Rounded Mplus 1c"
  # The BIOS writes dates as yyyy/MM/dd.
  | .clockDateFormat = "yyyy/MM/dd"
  # Slow, floaty glides instead of springy pops.
  | .springBounce = 0
  | .popoutAnimationDuration = 240
  | .modalAnimationDuration = 260
  | .notificationAnimationDuration = 280
  # Frosted glass over the fog, with a faint light edge.
  | .blurEnabled = true
  | .blurStrength = 48
  | .popupTransparency = 0.82
  | .blurLayerOutlineOpacity = 0.3
  | .sectionDividerOpacity = 0.15
  # Shadows become an indigo glow.
  | .m3ElevationColorMode = "custom"
  | .m3ElevationCustomColor = "#1b8fd0"
  | .m3ElevationIntensity = 16
  | .m3ElevationOpacity = 28
  # Bottom bar like the main menu: a black strip, no boxes around widgets, just
  # grey text and icons with the active bits in cyan.
  | .barConfigs |= map(.noBackground = false | .transparency = 0.88
        | .widgetOutlineEnabled = false | .widgetTransparency = 0
        | .fontScale = 1.08 | .shadowIntensity = 0)
  # Desktop: scene first so it maps first and stays under the other widgets.
  | .desktopWidgetInstances = ([scene("ps2_scene_desktop"; {showClockText: false})]
        + ((.desktopWidgetInstances // []) | map(select(.id != "ps2_scene_desktop"))))
  # Lock: last in the list = bottom of the stack. The scene draws its own clock,
  # so the stock clock (which would get auto-placed onto the password box) goes off.
  | .lockScreenWidgetInstances = (((.lockScreenWidgetInstances // [])
        | map(select(.id != "ps2_scene_lock"))
        | map(if .widgetType == "desktopClock" then .enabled = false else . end))
        + [scene("ps2_scene_lock"; {showClockText: true})])
'

# Static still for the wallpaper layer: shows in niri's overview backdrop and on
# the greeter, which can't run the plugin's live scene.
wp_dir=${XDG_PICTURES_DIR:-$HOME/Pictures}/ps2-bios
mkdir -p "$wp_dir"
cp -f "$(cd "$(dirname "$0")/.." && pwd)/wallpapers/ps2-crystal-clock-1080p.png" "$wp_dir/"
dms ipc call wallpaper set "$wp_dir/ps2-crystal-clock-1080p.png" >/dev/null || true
write_json "$settings" '.lockScreenWallpaperPath = "'"$wp_dir/ps2-crystal-clock-1080p.png"'"'

# niri: launch the standalone boot sequence before anything else, and make the
# backdrop black so the moment before it maps looks like a powered-on screen
# instead of a bare desktop. Every added line is tagged "ps2Bios" for revert.
niri_cfg=${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl
if [[ -f "$niri_cfg" ]]; then
    [[ -f "$niri_cfg.ps2-original" ]] || cp -a "$niri_cfg" "$niri_cfg.ps2-original"
    python3 -I - "$niri_cfg" "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ps2-intro" <<'PY'
import re, sys
path, intro = sys.argv[1], sys.argv[2]
s = open(path).read()
if 'ps2Bios boot sequence' not in s:
    spawn = ('// ps2Bios boot sequence: first thing on screen, before DMS loads\n'
             f'spawn-at-startup "qs" "-p" "{intro}" // ps2Bios\n')
    m = re.search(r'^spawn-at-startup', s, re.M)
    s = s[:m.start()] + spawn + s[m.start():] if m else s + '\n' + spawn
if 'backdrop-color "#000000" // ps2Bios' not in s:
    m = re.search(r'^overview\s*\{\n', s, re.M)
    line = '    backdrop-color "#000000" // ps2Bios\n'
    s = s[:m.end()] + line + s[m.end():] if m else s + '\noverview {\n' + line + '}\n'
open(path, 'w').write(s)
PY
    niri validate -c "$niri_cfg" >/dev/null 2>&1 || {
        echo "niri rejected the edited config, restoring it" >&2
        cp -a "$niri_cfg.ps2-original" "$niri_cfg"
    }
fi

if command -v gsettings >/dev/null; then
    gsettings set org.gnome.desktop.sound theme-name ps2-bios
    gsettings set org.gnome.desktop.sound event-sounds true
fi

echo ":: applied (run dms restart if the plugin doesn't show up)"
