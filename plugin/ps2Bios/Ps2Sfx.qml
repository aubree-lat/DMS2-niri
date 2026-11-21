import QtQuick
import QtMultimedia
import qs.Common
import qs.Services

// Plays the PS2 BIOS cues installed in ./sounds/<cue>.wav (built by scripts/build-sounds.sh).
// Cues that fire in quick succession (menu navigation, typing) get a few players
// so a new hit overlaps the tail of the last one instead of cutting it off.
Item {
    id: root

    property real volumeScale: 1.0
    property bool active: true

    readonly property var cues: ["popout_open", "popout_close", "modal_open", "modal_close", "navigate", "workspace", "window_open", "launch", "boot", "lock", "unlock", "key", "error"]
    readonly property var pooled: ({
            "navigate": 4,
            "key": 3
        })
    readonly property var slots: {
        const out = [];
        for (const cue of cues) {
            const n = pooled[cue] ?? 1;
            for (let i = 0; i < n; i++)
                out.push(cue);
        }
        return out;
    }
    readonly property real effectiveVolume: Math.max(0, Math.min(1, AudioService.notificationsVolume * volumeScale))

    property var _players: ({})
    property var _next: ({})
    property var _lastPlayed: ({})

    function play(cue, minGapMs) {
        if (!active || !SettingsData.soundsEnabled)
            return;
        const list = _players[cue];
        if (!list || list.length === 0)
            return;
        const now = Date.now();
        if (now - (_lastPlayed[cue] ?? 0) < (minGapMs ?? 60))
            return;
        const i = (_next[cue] ?? 0) % list.length;
        _next[cue] = i + 1;
        const player = list[i];
        if (player.status !== SoundEffect.Ready)
            return;
        _lastPlayed[cue] = now;
        if (player.playing)
            player.stop();
        player.play();
    }

    Instantiator {
        model: root.slots

        delegate: SoundEffect {
            required property string modelData
            source: Qt.resolvedUrl("sounds/" + modelData + ".wav")
            volume: root.effectiveVolume
        }

        onObjectAdded: (index, object) => {
            const cue = root.slots[index];
            const next = Object.assign({}, root._players);
            next[cue] = (next[cue] ?? []).concat([object]);
            root._players = next;
        }
    }
}
