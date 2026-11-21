import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

// Standalone boot sequence, spawned by niri at startup so it covers the screen
// seconds before DMS has loaded. Installed to ~/.config/quickshell/ps2-intro
// next to a copy of Ps2Intro.qml + shaders/ and a link to the plugin's sounds/.
// Quits when done (or straight away if it already played this login).
ShellRoot {
    id: shell

    readonly property string home: Quickshell.env("HOME")
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string configDir: Quickshell.env("DMS_CONFIG_DIR") || (home + "/.config/DankMaterialShell")

    FileView {
        id: pluginSettingsFile
        path: shell.configDir + "/plugin_settings.json"
        blockLoading: true
    }

    readonly property var cfg: {
        try {
            return JSON.parse(pluginSettingsFile.text() || "{}").ps2Bios ?? {};
        } catch (e) {
            return {};
        }
    }

    QtObject {
        id: sfx
        property var pending: ({})

        function play(name, minGapMs) {
            const player = name === "boot" ? bootSound : (name === "launch" ? launchSound : null);
            if (!player)
                return;
            if (player.status === SoundEffect.Ready)
                player.play();
            else
                pending[name] = true;
        }
    }

    SoundEffect {
        id: bootSound
        source: Qt.resolvedUrl("sounds/boot.wav")
        volume: Math.min(1, (shell.cfg.volume ?? 100) / 100)
        onStatusChanged: if (status === SoundEffect.Ready && sfx.pending.boot) {
            sfx.pending.boot = false;
            play();
        }
    }

    SoundEffect {
        id: launchSound
        source: Qt.resolvedUrl("sounds/launch.wav")
        volume: Math.min(1, (shell.cfg.volume ?? 100) / 100)
    }

    Ps2Intro {
        id: intro
        sfx: sfx
        title: shell.cfg.introText ?? ""
        renderScale: (shell.cfg.renderScale ?? 50) / 100
        grain: (shell.cfg.grain ?? 20) / 100
        orbCount: shell.cfg.orbs ?? 8
        desktopReady: false
        onFinished: Qt.quit()
    }

    // At login DMS is still loading; fade out only once the desktop clock scene
    // (the frame this sequence ends on) is actually on screen underneath.
    Process {
        id: desktopProbe
        command: ["sh", "-c", "niri msg layers 2>/dev/null | grep -q 'dms:desktop-widget:ps2Bios'"]
        onExited: exitCode => {
            if (exitCode === 0)
                intro.desktopReady = true;
        }
    }

    Timer {
        interval: 300
        repeat: true
        running: intro.running && !intro.desktopReady
        onTriggered: if (!desktopProbe.running) desktopProbe.running = true
    }

    Process {
        id: gate
        command: ["sh", "-c", "f=\"$XDG_RUNTIME_DIR/ps2bios.intro-played\"; [ -n \"$XDG_RUNTIME_DIR\" ] && [ ! -e \"$f\" ] && touch \"$f\""]
        onExited: exitCode => {
            if (exitCode === 0)
                intro.start();
            else
                Qt.quit();
        }
    }

    Component.onCompleted: {
        if ((shell.cfg.introEnabled ?? true) === false || (shell.cfg.enabled ?? true) === false) {
            Qt.quit();
            return;
        }
        gate.running = true;
    }
}
