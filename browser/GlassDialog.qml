import QtQuick

// Centered glass prompt used for rename / new folder / trash confirmation.
// Enter confirms, Escape cancels.
FocusScope {
    id: dlg

    property string title: ""
    property string message: ""
    property bool withInput: false
    property string confirmText: "confirm"
    property bool danger: false
    property alias text: input.text

    signal accepted(string value)
    signal rejected

    visible: false
    anchors.fill: parent
    z: 50

    function open(t, msg, initial, hasInput, confirmLabel, isDanger) {
        title = t;
        message = msg || "";
        withInput = !!hasInput;
        input.text = initial || "";
        confirmText = confirmLabel || "confirm";
        danger = !!isDanger;
        visible = true;
        if (withInput) {
            input.forceActiveFocus();
            const dot = input.text.lastIndexOf(".");
            input.select(0, dot > 0 ? dot : input.text.length);
        } else {
            keyCatcher.forceActiveFocus();
        }
    }

    function close() {
        visible = false;
    }

    Rectangle {
        anchors.fill: parent
        color: "#b0000000"
        MouseArea {
            anchors.fill: parent
            onClicked: {
                dlg.close();
                dlg.rejected();
            }
        }
    }

    Item {
        id: keyCatcher
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                dlg.close();
                dlg.rejected();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Y) {
                dlg.close();
                dlg.accepted(input.text);
                event.accepted = true;
            } else if (event.key === Qt.Key_N) {
                dlg.close();
                dlg.rejected();
                event.accepted = true;
            }
        }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 520)
        height: col.implicitHeight + 48
        radius: 4
        gradient: Gradient {
            GradientStop {
                position: 0
                color: "#f0141414"
            }
            GradientStop {
                position: 1
                color: "#f8060606"
            }
        }
        border.width: 1
        border.color: dlg.danger ? "#c0ff5a5a" : "#60ffffff"
        scale: dlg.visible ? 1 : 0.94
        Behavior on scale {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            spacing: 14

            Text {
                text: dlg.title
                color: "#d6d40a"
                font.family: "Rounded Mplus 1c"
                font.pixelSize: 20
                font.letterSpacing: 3
            }
            Text {
                visible: dlg.message !== ""
                width: parent.width
                text: dlg.message
                color: "#9a9aa4"
                font.family: "Rounded Mplus 1c"
                font.pixelSize: 14
                wrapMode: Text.WrapAnywhere
            }
            Rectangle {
                visible: dlg.withInput
                width: parent.width
                height: 38
                radius: 3
                color: "#60000000"
                border.width: 1
                border.color: input.activeFocus ? "#38cefa" : "#40ffffff"
                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: "#ffffff"
                    selectionColor: "#1d5fd6"
                    font.family: "Rounded Mplus 1c"
                    font.pixelSize: 15
                    clip: true
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            dlg.close();
                            dlg.rejected();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            dlg.close();
                            dlg.accepted(input.text);
                            event.accepted = true;
                        }
                    }
                }
            }
            Text {
                text: dlg.withInput ? "enter  " + dlg.confirmText + "      esc  cancel" : "enter  " + dlg.confirmText + "      esc  cancel"
                color: "#6a6a76"
                font.family: "Rounded Mplus 1c"
                font.pixelSize: 12
                font.letterSpacing: 2
            }
        }
    }
}
