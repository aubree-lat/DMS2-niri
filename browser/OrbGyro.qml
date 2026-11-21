import QtQuick
import QtQuick.Effects

// A small gyroscope of light: pairs of white-cored orbs riding a tilted ring
// that slowly precesses, with a soft cyan bloom and a faint orbit trail.
Item {
    id: gyro

    property real radius: Math.min(width, height) * 0.36
    property int pairs: 3
    property bool running: true
    property real t: 0

    width: 110
    height: 110

    Timer {
        interval: 16
        repeat: true
        running: gyro.running && gyro.visible
        onTriggered: gyro.t = (Date.now() / 1000) % 3600
    }

    readonly property real tilt: 1.05 + 0.25 * Math.sin(t * 0.35)
    readonly property real roll: t * 0.22

    function project(theta) {
        const x0 = Math.cos(theta) * radius;
        const y0 = Math.sin(theta) * radius;
        const y1 = y0 * Math.cos(tilt);
        const z = y0 * Math.sin(tilt);
        const cr = Math.cos(roll), sr = Math.sin(roll);
        return {
            x: width / 2 + x0 * cr - y1 * sr,
            y: height / 2 + x0 * sr + y1 * cr,
            z: z / radius
        };
    }

    Item {
        id: orbs
        anchors.fill: parent

        Canvas {
            id: trail
            anchors.fill: parent
            opacity: 0.45
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.lineWidth = 1.2;
                ctx.strokeStyle = "rgba(51, 140, 255, 0.55)";
                ctx.beginPath();
                for (let i = 0; i <= 64; i++) {
                    const p = gyro.project(i / 64 * Math.PI * 2);
                    if (i === 0)
                        ctx.moveTo(p.x, p.y);
                    else
                        ctx.lineTo(p.x, p.y);
                }
                ctx.stroke();
            }
            Connections {
                target: gyro
                function onTChanged() {
                    trail.requestPaint();
                }
            }
        }

        Repeater {
            model: gyro.pairs * 2
            delegate: Rectangle {
                required property int index
                readonly property real theta: gyro.t * 1.1 + Math.floor(index / 2) * (Math.PI * 2 / gyro.pairs) + (index % 2) * 0.32
                readonly property var p: gyro.project(theta)
                readonly property real size: 7 + 3.5 * (p.z * 0.5 + 0.5)
                x: p.x - size / 2
                y: p.y - size / 2
                width: size
                height: size
                radius: size / 2
                color: "#ffffff"
                opacity: 0.55 + 0.45 * (p.z * 0.5 + 0.5)
                z: p.z
            }
        }
    }

    // Bloom: a blurred, cyan-tinted copy of the orbs underneath the sharp ones.
    MultiEffect {
        anchors.fill: orbs
        source: orbs
        z: -1
        blurEnabled: true
        blur: 1.0
        blurMax: 32
        colorization: 1.0
        colorizationColor: "#33c2ff"
        brightness: 0.8
        scale: 1.6
    }
}
