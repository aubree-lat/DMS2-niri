#!/usr/bin/env bash
# Builds the PS2 BIOS sound files from Junomede/PS2-System-Sounds.
# The sounds are Sony's, so they are fetched at install time instead of being
# shipped in this repo.
#
#   build-sounds.sh <plugin-sounds-dir> <xdg-sound-theme-dir> [source-dir]
#
# Writes 16-bit PCM WAVs (QtMultimedia's SoundEffect can't play the source's
# 32-bit float WAVs) to:
#   <plugin-sounds-dir>/<cue>.wav           cues the ps2Bios plugin plays
#   <xdg-sound-theme-dir>/stereo/<event>.wav  freedesktop events DMS plays natively
set -euo pipefail

plugin_dir=${1:?plugin sounds dir}
theme_dir=${2:?sound theme dir}
src=${3:-}

command -v ffmpeg >/dev/null || { echo "ffmpeg is required" >&2; exit 1; }

cleanup=""
if [[ -z "$src" ]]; then
    cleanup=$(mktemp -d)
    git clone --quiet --depth 1 https://github.com/Junomede/PS2-System-Sounds.git "$cleanup/repo"
    src="$cleanup/repo/PS2-System-Sounds"
fi
trap '[[ -n "$cleanup" ]] && rm -rf "$cleanup"' EXIT

[[ -f "$src/deck_ui_navigation.wav" ]] || { echo "no PS2 sounds found in $src" >&2; exit 1; }

convert() {
    ffmpeg -v error -y -i "$src/deck_ui_$1.wav" -c:a pcm_s16le -ar 44100 -ac 2 "$2"
}

mkdir -p "$plugin_dir" "$theme_dir/stereo"

# plugin cue        <- SteamOS slot the pack replaced
declare -A cues=(
    [popout_open]=side_menu_fly_in
    [popout_close]=side_menu_fly_out
    [modal_open]=show_modal
    [modal_close]=hide_modal
    [navigate]=navigation
    [workspace]=into_game_detail
    [launch]=show_modal
    [boot]=launch_game
    [window_open]=default_activation
    [lock]=out_of_game_detail
    [unlock]=into_game_detail
    [key]=switch_toggle_on
    [error]=bumper_end_02
)
for cue in "${!cues[@]}"; do
    convert "${cues[$cue]}" "$plugin_dir/$cue.wav"
done

# freedesktop event  <- SteamOS slot
declare -A events=(
    [desktop-login]=launch_game
    [message]=toast
    [message-new-instant]=achievement_toast
    [audio-volume-change]=volume
    [power-plug]=switch_toggle_on
    [power-unplug]=switch_toggle_off
    [dialog-warning]=bumper_end_02
    [dialog-information]=toast
    [bell]=bumper_end_02
    [service-login]=launch_game
    [device-added]=switch_toggle_on
    [device-removed]=switch_toggle_off
    [screen-capture]=default_activation
    [complete]=default_activation
)
for ev in "${!events[@]}"; do
    convert "${events[$ev]}" "$theme_dir/stereo/$ev.wav"
done

cat > "$theme_dir/index.theme" <<'EOF'
[Sound Theme]
Name=PS2 BIOS
Comment=PlayStation 2 BIOS cues (Junomede/PS2-System-Sounds, sounds by Sony Interactive Entertainment)
Inherits=freedesktop
Directories=stereo

[stereo]
OutputProfile=stereo
EOF

echo "built ${#cues[@]} plugin cues and ${#events[@]} sound theme events"
