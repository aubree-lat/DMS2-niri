import QtQuick
import QtQuick.Effects
import Quickshell
import "Icons.js" as Icons

// One entry in the grid: a glass card holding the file's icon (or a thumbnail
// for images). The selected card lifts, glows, and its icon turns slowly in 3D.
Item {
    id: tile

    required property var entry
    required property int index
    property bool selected: false
    property bool dimmed: false
    property string home: ""

    signal clicked(var mouse)
    signal doubleClicked

    width: 150
    height: 172

    readonly property bool thumb: !entry.isDir && Icons.isImage(entry.suffix) && entry.size < 40 * 1024 * 1024
    readonly property string iconSource: {
        const rel = entry.path.startsWith(home + "/") ? entry.path.slice(home.length + 1) : (entry.path === home ? "" : undefined);
        const names = Icons.candidates(entry.isDir, entry.name, entry.suffix, rel);
        for (const n of names) {
            const p = Quickshell.iconPath(n, true);
            if (p)
                return p;
        }
        return Quickshell.iconPath("text-x-generic", true);
    }

    // Staggered arrival when a folder opens.
    opacity: 0
    property real rise: 14
    Component.onCompleted: arrive.start()
    SequentialAnimation {
        id: arrive
        PauseAnimation {
            duration: Math.min(tile.index, 36) * 14
        }
        ParallelAnimation {
            NumberAnimation {
                target: tile
                property: "opacity"
                to: 1
                duration: 260
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: tile
                property: "rise"
                to: 0
                duration: 320
                easing.type: Easing.OutCubic
            }
        }
    }

    Item {
        id: body
        width: 128
        height: 150
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8 + tile.rise - (tile.selected ? 6 : 0)
        scale: tile.selected ? 1.07 : 1.0
        Behavior on y {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        // Glow under the selected card.
        Rectangle {
            anchors.centerIn: card
            width: card.width + 18
            height: card.height + 18
            radius: 8
            color: "transparent"
            border.width: 9
            border.color: "#ffffff"
            opacity: tile.selected ? 0.22 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }
        }

        Rectangle {
            id: card
            width: 128
            height: 104
            radius: 3
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: tile.selected ? "#f0505049" : "#e83a3a36"
                }
                GradientStop {
                    position: 1
                    color: tile.selected ? "#f81c1c19" : "#f0131311"
                }
            }
            border.width: 1
            border.color: tile.selected ? "#f0ffffff" : "#38ffffff"
            Behavior on border.color {
                ColorAnimation {
                    duration: 200
                }
            }

            // Glass sheen across the top.
            Rectangle {
                x: 1
                y: 1
                width: parent.width - 2
                height: parent.height * 0.42
                radius: 2
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "#22ffffff"
                    }
                    GradientStop {
                        position: 1
                        color: "#00ffffff"
                    }
                }
            }

            Rectangle {
                anchors.centerIn: iconHolder
                width: 70
                height: 70
                radius: 35
                color: "#ffffff"
                opacity: tile.selected ? 0.55 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                    }
                }
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 40
                }
            }

            Item {
                id: iconHolder
                anchors.centerIn: parent
                width: tile.thumb ? 104 : 64
                height: tile.thumb ? 78 : 64

                transform: Rotation {
                    origin.x: iconHolder.width / 2
                    origin.y: iconHolder.height / 2
                    axis {
                        x: 0
                        y: 1
                        z: 0
                    }
                    angle: spin.angle
                }

                Image {
                    id: iconImg
                    anchors.fill: parent
                    visible: (!tile.thumb || thumbImg.status !== Image.Ready) && !tile.entry.isDir
                    source: tile.iconSource
                    sourceSize: Qt.size(128, 128)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                }

                // Breeze folders are recoloured by Plasma's colour scheme, so outside
                // KDE they come out grey: tint them crystal periwinkle instead.
                MultiEffect {
                    anchors.fill: parent
                    visible: tile.entry.isDir
                    source: iconImg
                    colorization: 1.0
                    colorizationColor: tile.selected ? "#ffffff" : "#c9c9c4"
                    brightness: tile.selected ? 0.8 : 0.4
                    contrast: 0.15
                }

                Rectangle {
                    anchors.fill: parent
                    visible: tile.thumb && thumbImg.status === Image.Ready
                    color: "#000000"
                    border.width: 1
                    border.color: "#50ffffff"
                    radius: 2
                    clip: true
                    Image {
                        id: thumbImg
                        anchors.fill: parent
                        anchors.margins: 1
                        source: tile.thumb ? "file://" + tile.entry.path.split("/").map(encodeURIComponent).join("/") : ""
                        sourceSize: Qt.size(208, 156)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        smooth: true
                    }
                }
            }

            // Slow turn while selected; eases back to face-on when deselected.
            QtObject {
                id: spin
                property real angle: 0
            }
            NumberAnimation {
                id: spinAnim
                target: spin
                property: "angle"
                from: 0
                to: 360
                duration: 5200
                loops: Animation.Infinite
                running: tile.selected
            }
            NumberAnimation {
                id: settle
                target: spin
                property: "angle"
                to: 0
                duration: 260
                easing.type: Easing.OutCubic
            }
            Connections {
                target: tile
                function onSelectedChanged() {
                    if (!tile.selected) {
                        spinAnim.stop();
                        if (spin.angle > 180)
                            spin.angle -= 360;
                        settle.restart();
                    }
                }
            }
        }

        Text {
            anchors.top: card.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: card.horizontalCenter
            width: 140
            horizontalAlignment: Text.AlignHCenter
            text: tile.entry.name
            color: tile.selected ? "#ffffff" : "#e2e2df"
            style: Text.Outline
            styleColor: "#a0000000"
            opacity: tile.entry.hidden ? 0.6 : 1
            font.family: "Rounded Mplus 1c"
            font.pixelSize: 14
            font.weight: tile.selected ? Font.Medium : Font.Normal
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => tile.clicked(mouse)
        onDoubleClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                tile.doubleClicked();
        }
    }
}
