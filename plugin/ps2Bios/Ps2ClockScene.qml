import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Full-screen animated crystal clock. Add it as a desktop widget (bottom of the
// stack) and/or a lock screen widget (last in the list so it sits underneath).
DesktopPluginComponent {
    id: root

    minWidth: 200
    minHeight: 150
    // Clamped to the screen by DMS on first placement, so new instances start full-screen.
    property real defaultWidth: 100000
    property real defaultHeight: 100000

    property var lockHost: null
    property var screen: null

    readonly property var globalCfg: SettingsData.pluginSettings["ps2Bios"] ?? ({})
    function opt(key, fallback) {
        const local = root.pluginData?.[key];
        if (local !== undefined)
            return local;
        const g = root.globalCfg[key];
        return g !== undefined ? g : fallback;
    }

    readonly property int fps: opt("fps", 24)
    readonly property real renderScale: opt("renderScale", 50) / 100
    readonly property bool followTheme: opt("followTheme", false)
    readonly property bool showClockText: opt("showClockText", root.lockScreen)
    readonly property bool use24h: opt("clock24h", SettingsData.use24HourClock ?? true)
    // "classic": time/date bottom-left over the purple backdrop; "sysconfig": the
    // System Configuration screen (bars, title, option label, prompts).
    readonly property bool sysConfigLock: root.lockScreen && opt("lockStyle", "classic") === "sysconfig"

    // On the lock screen the scene takes the System Configuration screen's purple.
    readonly property color prismA: root.lockScreen ? "#5560e6" : (followTheme ? Theme.primary : "#5a6cf0")
    readonly property color prismB: root.lockScreen ? "#8a74ff" : (followTheme ? Theme.tertiary : "#49d8c4")
    readonly property color orbColor: root.lockScreen ? "#d6dcff" : (followTheme ? Qt.lighter(Theme.primary, 1.6) : "#bff4ff")
    readonly property color bgColor: root.lockScreen ? "#2c2249" : (followTheme ? Theme.surfaceContainerLowest : "#0d0b26")

    readonly property bool animating: root.visible && root.width > 0 && (root.Window.window?.visible ?? true)


    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Rectangle {
        anchors.fill: parent
        color: root.bgColor
    }

    Item {
        id: stage
        width: Math.max(1, Math.round(root.width * root.renderScale))
        height: Math.max(1, Math.round(root.height * root.renderScale))
        scale: 1 / root.renderScale
        transformOrigin: Item.TopLeft
        layer.enabled: root.renderScale < 0.999 || root.lockScreen
        layer.smooth: true
        // Locked: drawn only through the blur below, like the menu's out-of-focus backdrop.
        visible: !root.lockScreen

        ShaderEffect {
            id: fx
            anchors.fill: parent
            property real iTime: 0
            property real hourValue: clock.hours + clock.minutes / 60
            property real minuteFrac: (clock.minutes + clock.seconds / 60) / 60
            property real glowStrength: 1.0
            property real grain: root.opt("grain", 20) / 100
            property real orbCount: root.opt("orbs", 8)
            property real spinSpeed: 0.25
            property real introT: 1000
            property real shiftX: root.lockScreen ? -0.3 : 0.12
            property vector2d resolution: Qt.vector2d(width, height)
            property color colA: root.prismA
            property color colB: root.prismB
            property color colOrb: root.orbColor
            property color colBg: root.bgColor
            fragmentShader: Qt.resolvedUrl("shaders/ps2clock.frag.qsb")
        }
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.lockScreen
        source: stage
        blurEnabled: true
        blur: 0.55
        blurMax: 24
    }

    LockSysConfig {
        anchors.fill: parent
        visible: root.lockScreen
        animate: root.lockScreen && root.animating
        use24h: root.use24h
        chrome: root.sysConfigLock
    }

    Timer {
        interval: Math.max(8, Math.round(1000 / Math.max(1, root.fps)))
        repeat: true
        running: root.animating
        // Wall-clock time base, shared with the boot sequence, so the frame it fades
        // out on is exactly the frame this scene is showing underneath.
        onTriggered: fx.iTime = (Date.now() / 1000) % 14400
    }

    Column {
        visible: root.showClockText && !root.sysConfigLock
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Math.round(root.height * 0.06)
        spacing: 2

        Text {
            text: Qt.formatTime(clock.date, root.use24h ? "HH:mm" : "h:mm AP")
            color: "#e6ecff"
            opacity: 0.85
            font.family: "Rounded Mplus 1c"
            font.pixelSize: Math.round(root.height * 0.05)
            font.letterSpacing: 2
        }
        Text {
            text: Qt.formatDate(clock.date, "dddd  d MMMM yyyy").toLowerCase()
            color: "#aab6e8"
            opacity: 0.7
            font.family: "Rounded Mplus 1c"
            font.pixelSize: Math.round(root.height * 0.018)
            font.letterSpacing: 3
        }
    }

    // Lock screen cues: a soft tick per keystroke, the "can't do that" bump on a wrong password.
    Ps2Sfx {
        id: sfx
        active: root.lockScreen && root.opt("lockSounds", true)
        volumeScale: root.opt("volume", 100) / 100
    }

    property int _lastLen: 0
    Connections {
        target: root.lockScreen ? root.lockHost : null
        ignoreUnknownSignals: true
        function onPasswordEdited(text) {
            const len = (text || "").length;
            if (len > root._lastLen)
                sfx.play("key", 40);
            root._lastLen = len;
        }
        function onAuthFailed() {
            root._lastLen = 0;
            sfx.play("error", 300);
        }
    }
}
