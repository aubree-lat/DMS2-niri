import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Adds PS2 BIOS cues to shell interactions DMS has no sound events for, and
// plays the boot sequence once per login.
PluginComponent {
    id: root

    readonly property var cfg: SettingsData.pluginSettings["ps2Bios"] ?? ({})
    readonly property bool uiSounds: cfg.uiSounds ?? true
    readonly property bool launcherSounds: cfg.launcherSounds ?? true
    readonly property bool workspaceSound: cfg.workspaceSound ?? true
    readonly property bool windowSound: cfg.windowSound ?? true
    readonly property bool lockSounds: cfg.lockSounds ?? true
    readonly property bool introEnabled: cfg.introEnabled ?? true

    property int _popoutCount: 0
    property var _popoutSet: []
    property int _modalCount: 0
    property real _lastModalChange: 0
    property int _windowCount: -1
    property bool _armed: false

    Ps2Sfx {
        id: sfx
        volumeScale: (root.cfg.volume ?? 100) / 100
    }

    Ps2Intro {
        id: intro
        sfx: sfx
        title: root.cfg.introText ?? ""
        renderScale: (root.cfg.renderScale ?? 50) / 100
        grain: (root.cfg.grain ?? 20) / 100
        orbCount: root.cfg.orbs ?? 8
    }

    // Once per login: XDG_RUNTIME_DIR is wiped at logout, so DMS restarts don't
    // replay it. Normally the standalone launcher spawned by niri (intro/shell.qml)
    // has already played it and set the marker before DMS even starts.
    Process {
        id: introGate
        command: ["sh", "-c", "f=\"$XDG_RUNTIME_DIR/ps2bios.intro-played\"; [ -n \"$XDG_RUNTIME_DIR\" ] && [ ! -e \"$f\" ] && touch \"$f\""]
        onExited: exitCode => {
            if (exitCode !== 0)
                return;
            if (root.introEnabled)
                intro.start();
            else
                sfx.play("boot", 0);
        }
    }

    IpcHandler {
        target: "ps2bios"
        function intro(): string {
            intro.start();
            return "playing";
        }
        function cue(name: string): string {
            sfx.play(name, 0);
            return "ok";
        }
    }

    // Ignore the burst of state changes while the shell starts up.
    Timer {
        interval: 4000
        running: true
        onTriggered: {
            root._windowCount = (NiriService.windows || []).length;
            root._armed = true;
        }
    }

    Timer {
        interval: 600
        running: true
        onTriggered: introGate.running = true
    }

    function _liveValues(map) {
        const out = [];
        for (const k in map) {
            if (map[k])
                out.push(map[k]);
        }
        return out;
    }

    // ---- app launchers: navigation ticks, launch cue, their own open/close ----
    // Two launchers exist: the Super+Space launcher and the Alt+Space spotlight bar.

    property real _launcherToggledAt: 0
    property real _launchedAt: 0
    readonly property bool anyLauncherOpen: (PopoutService.dankLauncherV2Modal?.spotlightOpen ?? false) || (PopoutService.spotlightBarModal?.spotlightOpen ?? false)

    component LauncherHook: Item {
        id: hook
        property var modal: null
        readonly property var controller: modal?.spotlightContent?.controller ?? null
        property real quietUntil: 0
        property bool navPending: false

        function flushNav() {
            if (!navPending)
                return;
            navPending = false;
            // A click selects the row and launches it in one go: only the launch cue.
            if (Date.now() < quietUntil || Date.now() - root._launchedAt < 400)
                return;
            sfx.play("navigate", 45);
        }

        Connections {
            target: hook.modal
            ignoreUnknownSignals: true
            function onSpotlightOpenChanged() {
                const now = Date.now();
                root._launcherToggledAt = now;
                if (!root._armed || !root.launcherSounds)
                    return;
                if (hook.modal.spotlightOpen) {
                    hook.quietUntil = now + 400;
                    sfx.play("popout_open", 150);
                } else {
                    // DMS closes the launcher from inside the same itemExecuted signal,
                    // before our handler has seen the launch; decide once it has.
                    closeCheck.restart();
                }
            }
        }

        Timer {
            id: closeCheck
            interval: 120
            onTriggered: {
                if (Date.now() - root._launchedAt > 900)
                    sfx.play("popout_close", 150);
            }
        }

        Connections {
            target: hook.controller
            ignoreUnknownSignals: true
            function onSelectedFlatIndexChanged() {
                if (!root.launcherSounds || !hook.modal?.spotlightOpen)
                    return;
                // Searches re-select programmatically; deciding a tick later lets
                // the search signals that follow in the same call mark it as such.
                hook.navPending = true;
                Qt.callLater(hook.flushNav);
            }
            function onQueryChanged() {
                hook.quietUntil = Date.now() + 250;
            }
            function onSearchCompleted() {
                hook.quietUntil = Math.max(hook.quietUntil, Date.now() + 150);
            }
            function onModeChanged() {
                hook.quietUntil = Date.now() + 250;
            }
            function onItemExecuted() {
                root._noteLaunch();
                if (root.launcherSounds)
                    sfx.play("launch", 200);
            }
        }
    }

    LauncherHook {
        modal: PopoutService.dankLauncherV2Modal
    }
    LauncherHook {
        modal: PopoutService.spotlightBarModal
    }

    // A launch already played its chime, so the window it opens stays quiet,
    // however long the app takes to start (plus splash-then-main-window pairs).
    property real _launchPendingUntil: 0
    property real _windowQuietUntil: 0

    function _noteLaunch() {
        _launchedAt = Date.now();
        _launchPendingUntil = _launchedAt + 20000;
    }

    function _windowOpened() {
        const now = Date.now();
        if (now < _launchPendingUntil) {
            _launchPendingUntil = 0;
            _windowQuietUntil = now + 2500;
            return;
        }
        if (now < _windowQuietUntil)
            return;
        _windowQuietUntil = now + 2500;
        sfx.play("window_open", 0);
    }

    // ---- popouts and other modals ----

    Connections {
        target: PopoutManager
        function onPopoutChanged() {
            const live = root._liveValues(PopoutManager.currentPopoutsByScreen);
            const count = live.length;
            const prev = root._popoutSet;
            const swapped = count > 0 && count === root._popoutCount && live.some(p => !prev.includes(p));
            const recentModal = Date.now() - root._lastModalChange < 250;
            if (root._armed && root.uiSounds && !recentModal) {
                if (count > root._popoutCount)
                    sfx.play("popout_open", 120);
                else if (count < root._popoutCount)
                    sfx.play("popout_close", 120);
                else if (swapped)
                    sfx.play("navigate", 120);
            }
            root._popoutCount = count;
            root._popoutSet = live;
        }
    }

    property int _pendingModalDelta: 0
    Timer {
        id: modalCueTimer
        interval: 60
        onTriggered: {
            const delta = root._pendingModalDelta;
            root._pendingModalDelta = 0;
            // The launcher has its own cues above.
            if (Date.now() - root._launcherToggledAt < 400 || root.anyLauncherOpen)
                return;
            if (delta > 0)
                sfx.play("modal_open", 150);
            else if (delta < 0)
                sfx.play("modal_close", 150);
        }
    }

    Connections {
        target: ModalManager
        function onModalChanged() {
            const count = root._liveValues(ModalManager.currentModalsByScreen).length;
            if (root._armed && root.uiSounds && !SessionService.locked) {
                root._pendingModalDelta += count - root._modalCount;
                modalCueTimer.restart();
            }
            root._modalCount = count;
            root._lastModalChange = Date.now();
        }
    }

    // ---- workspaces, windows, lock ----

    Connections {
        target: NiriService
        function onFocusedWorkspaceIndexChanged() {
            if (root._armed && root.workspaceSound && !SessionService.locked)
                sfx.play("workspace", 150);
        }
        function onWindowsChanged() {
            const count = (NiriService.windows || []).length;
            if (root._armed && root.windowSound && root._windowCount >= 0 && count > root._windowCount && !SessionService.locked)
                root._windowOpened();
            root._windowCount = count;
        }
    }

    Connections {
        target: SessionService
        function onSessionLocked() {
            if (root.lockSounds)
                sfx.play("lock", 500);
        }
        function onSessionUnlocked() {
            if (root.lockSounds)
                sfx.play("unlock", 500);
        }
    }
}
