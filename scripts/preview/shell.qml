import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    PanelWindow {
        id: win
        anchors { top: true; left: true }
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "ps2-preview"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}

        property var times: (Quickshell.env("PS2_TIMES") || "3,21,47").split(",").map(Number)
        property int idx: 0

        Item {
            id: stage
            width: Number(Quickshell.env("PS2_W") || 960); height: Number(Quickshell.env("PS2_H") || 540)
            ShaderEffect {
                id: fx
                anchors.fill: parent
                property real iTime: win.times[win.idx]
                property real hourValue: Number(Quickshell.env("PS2_HOUR") || 10.3)
                property real minuteFrac: Number(Quickshell.env("PS2_MIN") || 0.62)
                property real glowStrength: 1.0
                property real grain: 0.2
                property real orbCount: 8
                property real spinSpeed: 0.25
                property real introT: Quickshell.env("PS2_INTRO") === "follow" ? iTime : Number(Quickshell.env("PS2_INTRO") || 1000)
                property real shiftX: Number(Quickshell.env("PS2_SHIFT") || 0.12)
                property vector2d resolution: Qt.vector2d(width, height)
                property color colA: "#5a6cf0"
                property color colB: "#49d8c4"
                property color colOrb: "#bff4ff"
                property color colBg: "#0d0b26"
                fragmentShader: "file://" + Quickshell.env("PS2_QSB")
            }
        }
        Timer {
            interval: 700; running: true; repeat: true
            onTriggered: stage.grabToImage(r => {
                r.saveToFile((Quickshell.env("PS2_OUT") || "/tmp/ps2-frame") + win.idx + ".png");
                if (win.idx === win.times.length - 1) Qt.quit(); else win.idx++;
            })
        }
    }
}
