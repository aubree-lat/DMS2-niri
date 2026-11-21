#!/usr/bin/env bash
# Extracts the system menu (OSD) and boot sound samples from your own PS2 BIOS.
#
#   extract-bios-sounds.sh [BIOS] [OUTDIR]
#
# BIOS defaults to the one PCSX2 (flatpak) is set to use; OUTDIR to
# ~/.local/share/ps2-bios-sounds. Writes raw/ (22.05 kHz mono, as stored) and
# 44k/ (44.1 kHz stereo s16, what QtMultimedia plays best), osd/ and boot/ in each,
# and rendered/ (the sounds as the BIOS actually plays them, see tools/ps2snd.py).
# How it works: ROMDIR → SNDIMAGE (itself a ROMDIR) → SNDOSDDB / SNDBOOTB, which
# are LZ-compressed (tools/osdlz.py) raw SPU2 ADPCM banks (tools/spuadpcm.py).
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
bios=${1:-}
if [[ -z $bios ]]; then
    # the bios pcsx2 is set to use (flatpak or native install)
    for pcsx2 in "$HOME/.var/app/net.pcsx2.PCSX2/config/PCSX2" "${XDG_CONFIG_HOME:-$HOME/.config}/PCSX2"; do
        name=$(sed -n 's/^BIOS = //p' "$pcsx2/inis/PCSX2.ini" 2>/dev/null | head -1)
        [[ -n $name && -f "$pcsx2/bios/$name" ]] && { bios=$pcsx2/bios/$name; break; }
    done
fi
out=${2:-${XDG_DATA_HOME:-$HOME/.local/share}/ps2-bios-sounds}
[[ -n $bios && -f $bios ]] || { echo "no bios found; pass the path to your own ps2 bios dump" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 -I "$here/tools/romdir.py" "$bios" "$work" SNDIMAGE >/dev/null
python3 -I "$here/tools/romdir.py" "$work/SNDIMAGE" "$work/snd" >/dev/null
for part in OSDDH OSDDB BOOTH BOOTB BOOTS; do
    python3 -I "$here/tools/osdlz.py" "$work/snd/SND$part" "$work/$part.raw" >/dev/null
done
cp "$work/OSDDB.raw" "$work/OSDD.bank"
cp "$work/BOOTB.raw" "$work/BOOT.bank"

rm -rf "$out"
mkdir -p "$out/raw" "$out/44k"
python3 -I "$here/tools/spuadpcm.py" "$work/OSDD.bank" "$work/osd" 22050 >/dev/null
python3 -I "$here/tools/spuadpcm.py" "$work/BOOT.bank" "$work/boot" 22050 >/dev/null

# Names for the OSD bank, by sample index (identified 2026-11-21 against
# Junomede's pack and by ear-free analysis: envelopes, spectra, loop flags).
declare -A osd=(
    [08]=enter-confirm
    [12]=back-cancel
    [10]=select-click
    [02]=swell-a
    [04]=swell-b
    [00]=tone-bright-loop
    [06]=tone-soft-loop
)
mkdir -p "$out/raw/osd" "$out/raw/boot" "$out/44k/osd" "$out/44k/boot"
for f in "$work"/osd/*.wav; do
    idx=$(basename "$f" | cut -c1-2)
    [[ -n ${osd[$idx]:-} ]] || continue
    cp "$f" "$out/raw/osd/${osd[$idx]}.wav"
done
for f in "$work"/boot/*.wav; do
    # Skip the one-frame padding blocks between samples.
    (( $(stat -c %s "$f") > 2000 )) || continue
    idx=$(basename "$f" | cut -c1-2)
    cp "$f" "$out/raw/boot/boot-layer-$idx.wav"
done
for f in "$out"/raw/*/*.wav; do
    rel=${f#"$out/raw/"}
    ffmpeg -v error -y -i "$f" -ar 44100 -ac 2 -c:a pcm_s16le "$out/44k/$rel"
done
# Rendered the way the BIOS plays them (tools/ps2snd.py): every OSD voice preset,
# the cursor tick and edge bump identified from a PCSX2 recording, and the boot
# jingle (SNDBOOTS through the boot bank, plus the reconstructed noise rush).
mkdir -p "$out/rendered"
python3 -I "$here/tools/ps2snd.py" osd "$work/OSDDH.raw" "$work/OSDDB.raw" "$out/rendered" >/dev/null
cp "$out/rendered/osd-05.wav" "$out/rendered/cursor-tick.wav"
cp "$out/rendered/osd-03.wav" "$out/rendered/edge-bump.wav"
python3 -I "$here/tools/ps2snd.py" boot "$work/BOOTH.raw" "$work/BOOTB.raw" "$work/BOOTS.raw" "$out/rendered/boot-jingle.wav" >/dev/null

echo "extracted to $out"
ls "$out/raw/osd" "$out/raw/boot" "$out/rendered"
