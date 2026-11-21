import QtQuick
import QtQuick3D
import Quickshell

// Lock screen dressed as the console's System Configuration screen: black
// letterbox bars with the date (left) and time (right) on top, glass cubes
// tumbling over the blurred prism clock, a yellow title and a cyan option label
// above DMS's password dots (which sit at the screen centre), prompts below.
Item {
    id: lock

    property bool use24h: true
    property bool animate: true

    readonly property color yellow: "#d6d40a"
    readonly property color cyan: "#38cefa"
    readonly property color outline: "#b0000000"
    readonly property real barTop: Math.round(height * 0.105)
    readonly property real barBottom: Math.round(height * 0.115)

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // ---- tumbling glass cubes ----
    View3D {
        id: view
        x: 0
        y: lock.barTop
        width: lock.width * 0.55
        height: lock.height - lock.barTop - lock.barBottom
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
        }

        PerspectiveCamera {
            position: Qt.vector3d(0, 0, 900)
            fieldOfView: 40
        }
        DirectionalLight {
            eulerRotation.x: -35
            eulerRotation.y: -30
            brightness: 1.4
        }
        DirectionalLight {
            eulerRotation.x: 20
            eulerRotation.y: 140
            brightness: 0.5
            color: "#b8a8ff"
        }

        Repeater3D {
            // x, y, z, size, spin rate (deg/s) per axis, solid blue?
            model: [
                [-230, 180, 0, 1.15, [23, 31, 11], true],
                [-300, -40, -120, 0.95, [-17, 26, 19], false],
                [-110, 40, 80, 1.05, [29, -21, 13], false],
                [-250, -230, 40, 1.0, [14, 18, -27], false],
                [-60, -210, -60, 0.85, [-25, 12, 21], false],
                [60, 230, -200, 0.8, [19, -28, 9], false]
            ]
            delegate: Model {
                required property var modelData
                source: "#Cube"
                position: Qt.vector3d(modelData[0], modelData[1], modelData[2])
                scale: Qt.vector3d(modelData[3] * 0.78, modelData[3] * 0.78, modelData[3] * 0.78)
                property real t: 0
                eulerRotation: Qt.vector3d(t * modelData[4][0], t * modelData[4][1], t * modelData[4][2])
                NumberAnimation on t {
                    from: 0
                    to: 3600
                    duration: 3600 * 1000
                    loops: Animation.Infinite
                    running: lock.animate
                }
                materials: PrincipledMaterial {
                    baseColor: modelData[5] ? "#2f7dff" : "#d8d4ff"
                    emissiveFactor: modelData[5] ? Qt.vector3d(0.08, 0.25, 0.9) : Qt.vector3d(0.05, 0.05, 0.09)
                    metalness: 0.0
                    roughness: 0.18
                    opacity: modelData[5] ? 0.92 : 0.5
                    alphaMode: PrincipledMaterial.Blend
                    cullMode: PrincipledMaterial.NoCulling
                }
            }
        }
    }

    // ---- centre: title, option, (password dots are DMS's own widget, at the centre) ----
    Text {
        id: title
        anchors.horizontalCenter: parent.horizontalCenter
        y: lock.height / 2 - lock.height * 0.165
        text: "Screen Locked"
        color: lock.yellow
        style: Text.Outline
        styleColor: lock.outline
        font.family: "Rounded Mplus 1c"
        font.pixelSize: Math.round(lock.height * 0.05)
        font.weight: Font.Medium
    }
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        y: lock.height / 2 - lock.height * 0.095
        width: optionText.implicitWidth
        height: optionText.implicitHeight
        Text {
            id: optionText
            text: "Password"
            color: lock.cyan
            style: Text.Outline
            styleColor: lock.outline
            font.family: "Rounded Mplus 1c"
            font.pixelSize: Math.round(lock.height * 0.05)
            font.weight: Font.Medium
        }
        // The little up/down selector beside the option.
        Column {
            anchors.left: optionText.right
            anchors.leftMargin: lock.height * 0.025
            anchors.verticalCenter: optionText.verticalCenter
            spacing: 2
            Repeater {
                model: ["▲", "▼"]
                delegate: Text {
                    required property string modelData
                    text: modelData
                    color: "#e8e8ee"
                    style: Text.Outline
                    styleColor: lock.outline
                    font.pixelSize: Math.round(lock.height * 0.018)
                }
            }
        }
    }

    // ---- letterbox bars ----
    Rectangle {
        width: parent.width
        height: lock.barTop
        color: "#000000"
        Text {
            x: Math.round(lock.width * 0.032)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(lock.barTop * 0.12)
            text: Qt.formatDate(clock.date, "yyyy/MM/dd")
            color: "#ededed"
            font.family: "Rounded Mplus 1c"
            font.pixelSize: Math.round(lock.height * 0.042)
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: Math.round(lock.width * 0.032)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(lock.barTop * 0.12)
            spacing: Math.round(lock.height * 0.012)
            Text {
                readonly property bool day: clock.hours >= 6 && clock.hours < 18
                anchors.verticalCenter: parent.verticalCenter
                text: day ? "☀" : "☾"
                color: "#ededed"
                font.pixelSize: Math.round(lock.height * 0.032)
            }
            Text {
                text: Qt.formatTime(clock.date, lock.use24h ? "HH:mm:ss" : "h:mm:ss AP")
                color: "#ededed"
                font.family: "Rounded Mplus 1c"
                font.pixelSize: Math.round(lock.height * 0.042)
            }
        }
    }

    Rectangle {
        y: lock.height - lock.barBottom
        width: parent.width
        height: lock.barBottom
        color: "#000000"
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Math.round(lock.width * 0.03)
            y: Math.round(lock.barBottom * 0.18)
            spacing: Math.round(lock.width * 0.035)
            Repeater {
                model: [["⏎", "#8c8cff", "Unlock"], ["⌫", "#ff5a5a", "Delete"]]
                delegate: Row {
                    required property var modelData
                    spacing: Math.round(lock.height * 0.01)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData[0]
                        color: modelData[1]
                        font.pixelSize: Math.round(lock.height * 0.034)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData[2]
                        color: "#e2e2e2"
                        font.family: "Rounded Mplus 1c"
                        font.pixelSize: Math.round(lock.height * 0.036)
                    }
                }
            }
        }
    }
}
