import QtQuick
import Quickshell
import Quickshell.Wayland

// Boot sequence: orbs streak in out of the dark and lock into the ring with a
// flash, the hour prisms grow outward (optional text fades in at the centre),
// then it dissolves into the desktop. Click or any key skips it.
//
// It is framed exactly like the desktop clock scene and runs on the same
// wall-clock time, so the final frame is the frame the desktop is already
// showing underneath and the fade is seamless.
Scope {
    id: root

    property string title: ""
    property real renderScale: 0.5
    property real grain: 0.2
    property real orbCount: 8
    property var sfx: null

    // Hold on the finished scene until the desktop scene underneath exists
    // (at login DMS can still be loading), up to maxHold seconds.
    property bool desktopReady: true
    property real maxHold: 8

    // The shader's boot timeline is authored over ~5 s; play it this much faster.
    readonly property real speed: 1.75
    readonly property real mainLength: 3.6
    readonly property real fadeLength: 1.2

    property bool running: false
    property real elapsed: 0
    property real wallTime: 0
    property real fadeStart: -1
    property real _start: 0
    property bool _flashCuePlayed: false

    signal finished

    readonly property string resolvedTitle: (title || "").toLowerCase()
    readonly property real fade: fadeStart < 0 ? 1 : 1 - Math.min(1, Math.max(0, (elapsed - fadeStart) / fadeLength))

    function start() {
        _start = Date.now();
        elapsed = 0;
        fadeStart = -1;
        _flashCuePlayed = false;
        wallTime = (Date.now() / 1000) % 14400;
        running = true;
        sfx?.play("boot", 0);
    }

    function skip() {
        if (running && fadeStart < 0)
            fadeStart = elapsed;
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Timer {
        interval: 16
        repeat: true
        running: root.running
        onTriggered: {
            const now = Date.now();
            root.elapsed = (now - root._start) / 1000;
            root.wallTime = (now / 1000) % 14400;
            if (root.fadeStart < 0 && root.elapsed >= root.mainLength && (root.desktopReady || root.elapsed >= root.mainLength + root.maxHold))
                root.fadeStart = root.elapsed;
            if (root.fadeStart >= 0 && root.elapsed >= root.fadeStart + root.fadeLength) {
                root.running = false;
                root.finished();
            }
        }
    }

    Variants {
        model: root.running ? Quickshell.screens : []

        PanelWindow {
            id: win
            required property var modelData

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "dms:ps2-intro"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Item {
                id: content
                anchors.fill: parent
                opacity: root.fade
                focus: true
                Keys.onPressed: event => {
                    root.skip();
                    event.accepted = true;
                }

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                }

                Item {
                    width: Math.max(1, Math.round(parent.width * root.renderScale))
                    height: Math.max(1, Math.round(parent.height * root.renderScale))
                    scale: 1 / root.renderScale
                    transformOrigin: Item.TopLeft
                    layer.enabled: root.renderScale < 0.999
                    layer.smooth: true

                    ShaderEffect {
                        anchors.fill: parent
                        property real iTime: root.wallTime
                        property real hourValue: clock.hours + clock.minutes / 60
                        property real minuteFrac: (clock.minutes + clock.seconds / 60) / 60
                        property real glowStrength: 1.0
                        property real grain: root.grain
                        property real orbCount: root.orbCount
                        property real spinSpeed: 0.25
                        property real shiftX: 0.12
                        property real introT: root.elapsed * root.speed
                        property vector2d resolution: Qt.vector2d(width, height)
                        property color colA: "#5a6cf0"
                        property color colB: "#49d8c4"
                        property color colOrb: "#bff4ff"
                        property color colBg: "#0d0b26"
                        fragmentShader: Qt.resolvedUrl("shaders/ps2clock.frag.qsb")
                    }
                }

                Text {
                    // The ring's centre, matching the desktop scene's off-centre framing.
                    x: parent.width / 2 + parent.height * 0.12 - width / 2
                    y: parent.height / 2 - height / 2
                    text: root.resolvedTitle
                    color: "#eef3ff"
                    font.family: "Rounded Mplus 1c"
                    font.pixelSize: Math.round(parent.height * 0.034)
                    font.letterSpacing: Math.round(parent.height * 0.012)
                    opacity: Math.min(1, Math.max(0, (root.elapsed - 2.4) / 0.8))
                    style: Text.Outline
                    styleColor: "#40bff4ff"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.skip()
                }
            }
        }
    }
}
