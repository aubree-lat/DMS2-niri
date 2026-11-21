import QtQuick
import QtQuick.Effects
import QtMultimedia
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons

// PS2 Browser: a file browser in the PS2 BIOS look. Run through the
// `ps2-browser [path]` wrapper, which passes the start folder in
// PS2_BROWSER_DIR (and a file to preselect in PS2_BROWSER_SELECT).
ShellRoot {
    id: app

    readonly property string home: Quickshell.env("HOME")
    readonly property string configDir: Quickshell.env("DMS_CONFIG_DIR") || (home + "/.config/DankMaterialShell")
    readonly property string shotPath: Quickshell.env("PS2_BROWSER_SHOT") || ""

    property string dir: normalize(Quickshell.env("PS2_BROWSER_DIR") || home)
    property string pendingSelect: Quickshell.env("PS2_BROWSER_SELECT") || ""
    property var backStack: []
    property var forwardStack: []
    property bool showHidden: false
    property string filter: ""
    property bool filtering: false
    property var entries: []
    property bool placesFocused: false
    property int placeIndex: 0
    property string status: ""

    readonly property var current: grid.currentIndex >= 0 && grid.currentIndex < entries.length ? entries[grid.currentIndex] : null
    readonly property string dirName: dir === "/" ? "/" : (dir === home ? "home" : dir.slice(dir.lastIndexOf("/") + 1))

    function normalize(p) {
        if (p.startsWith("file://"))
            p = decodeURIComponent(p.slice(7));
        if (p.startsWith("~"))
            p = home + p.slice(1);
        while (p.length > 1 && p.endsWith("/"))
            p = p.slice(0, -1);
        return p || "/";
    }

    function toUrl(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/");
    }

    function parentOf(p) {
        if (p === "/")
            return "/";
        const i = p.lastIndexOf("/");
        return i <= 0 ? "/" : p.slice(0, i);
    }

    function go(path, opts) {
        opts = opts || {};
        path = normalize(path);
        if (path === dir)
            return;
        if (!opts.noHistory) {
            backStack = backStack.concat([dir]);
            forwardStack = [];
        }
        filter = "";
        filtering = false;
        pendingSelect = opts.select || "";
        dir = path;
        sfx.play(opts.back ? "popout_close" : "launch");
    }

    function goUp() {
        if (dir === "/") {
            sfx.play("error");
            return;
        }
        const name = dir.slice(dir.lastIndexOf("/") + 1);
        go(parentOf(dir), {
            select: name,
            back: true
        });
    }

    function goBack() {
        if (backStack.length === 0) {
            sfx.play("error");
            return;
        }
        const prev = backStack[backStack.length - 1];
        backStack = backStack.slice(0, -1);
        forwardStack = forwardStack.concat([dir]);
        const from = dir;
        go(prev, {
            noHistory: true,
            back: true,
            select: parentOf(from) === prev ? from.slice(from.lastIndexOf("/") + 1) : ""
        });
    }

    function goForward() {
        if (forwardStack.length === 0) {
            sfx.play("error");
            return;
        }
        const next = forwardStack[forwardStack.length - 1];
        forwardStack = forwardStack.slice(0, -1);
        backStack = backStack.concat([dir]);
        go(next, {
            noHistory: true
        });
    }

    function openEntry(e) {
        if (!e)
            return;
        if (e.isDir) {
            go(e.path);
        } else {
            sfx.play("launch");
            Quickshell.execDetached(["xdg-open", e.path]);
        }
    }

    // ---- listing ----

    FolderListModel {
        id: folder
        folder: app.toUrl(app.dir)
        showDirsFirst: true
        showHidden: app.showHidden
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        sortCaseSensitive: false
        onStatusChanged: if (status === FolderListModel.Ready)
            rebuild.restart()
        onCountChanged: rebuild.restart()
    }

    Connections {
        target: folder
        function onDataChanged() {
            rebuild.restart();
        }
        function onModelReset() {
            rebuild.restart();
        }
    }

    Timer {
        id: rebuild
        interval: 30
        onTriggered: app.rebuildEntries()
    }

    onFilterChanged: rebuild.restart()

    function rebuildEntries() {
        const keepName = pendingSelect || (current ? current.name : "");
        const f = filter.toLowerCase();
        const list = [];
        for (let i = 0; i < folder.count; i++) {
            const name = folder.get(i, "fileName");
            if (f && name.toLowerCase().indexOf(f) < 0)
                continue;
            list.push({
                name: name,
                path: folder.get(i, "filePath"),
                isDir: folder.get(i, "fileIsDir"),
                suffix: folder.get(i, "fileSuffix"),
                size: folder.get(i, "fileSize"),
                modified: folder.get(i, "fileModified"),
                hidden: name.startsWith(".")
            });
        }
        const dirChanged = list.length === 0 || entries.length === 0 || (list[0] && entries[0] && parentOf(list[0].path) !== parentOf(entries[0].path));
        entries = list;
        let idx = keepName ? list.findIndex(e => e.name === keepName) : -1;
        grid.silent = true;
        grid.currentIndex = idx >= 0 ? idx : (list.length ? 0 : -1);
        grid.silent = false;
        if (idx >= 0)
            grid.positionViewAtIndex(idx, GridView.Contain);
        else if (dirChanged)
            grid.positionViewAtBeginning();
        pendingSelect = "";
    }

    // ---- places ----

    readonly property var places: {
        const p = [
            { label: "home", path: home },
            { label: "desktop", path: home + "/Desktop" },
            { label: "documents", path: home + "/Documents" },
            { label: "downloads", path: home + "/Downloads" },
            { label: "pictures", path: home + "/Pictures" },
            { label: "music", path: home + "/Music" },
            { label: "videos", path: home + "/Videos" },
            { label: "system", path: "/" },
            { label: "trash", path: home + "/.local/share/Trash/files" }
        ];
        for (const d of mounts)
            p.push({ label: d.slice(d.lastIndexOf("/") + 1), path: d, drive: true });
        return p;
    }

    // Mounted drives under /mnt and /run/media/$USER (only real mount points).
    property var mounts: []
    Process {
        id: mountScan
        running: true
        command: ["sh", "-c", "for d in /mnt/* \"/run/media/$USER\"/*; do [ -d \"$d\" ] && mountpoint -q \"$d\" && printf '%s\\n' \"$d\"; done; true"]
        stdout: StdioCollector {
            onStreamFinished: app.mounts = text.split("\n").filter(l => l.length > 0)
        }
    }

    // ---- file operations ----

    Component {
        id: procComponent
        Process {
            id: proc
            property var done: null
            stderr: StdioCollector {
                id: errOut
            }
            onExited: exitCode => {
                if (done)
                    done(exitCode, errOut.text);
                proc.destroy();
            }
        }
    }

    function run(cmd, done) {
        const p = procComponent.createObject(app, {
            command: cmd,
            done: done
        });
        p.running = true;
    }

    function flash(msg) {
        status = msg;
        statusTimer.restart();
    }
    Timer {
        id: statusTimer
        interval: 2600
        onTriggered: app.status = ""
    }

    function askTrash() {
        if (!current)
            return;
        sfx.play("modal_open");
        dialog.mode = "trash";
        dialog.open("Move to trash?", current.name, "", false, "trash", true);
    }

    function askRename() {
        if (!current)
            return;
        sfx.play("modal_open");
        dialog.mode = "rename";
        dialog.open("Rename", "", current.name, true, "rename");
    }

    function askNewFolder() {
        sfx.play("modal_open");
        dialog.mode = "mkdir";
        dialog.open("New folder", "Inside " + dir, "new folder", true, "create");
    }

    function onDialogAccepted(value) {
        const target = current;
        if (dialog.mode === "trash" && target) {
            run(["dms", "trash", "put", target.path], (code, err) => {
                if (code === 0) {
                    sfx.play("modal_close");
                    flash("moved " + target.name + " to trash");
                } else {
                    sfx.play("error");
                    flash("couldn't trash: " + (err.trim() || "exit " + code));
                }
            });
        } else if (dialog.mode === "rename" && target) {
            const name = value.trim();
            if (!name || name.indexOf("/") >= 0 || name === target.name) {
                if (name !== target.name)
                    sfx.play("error");
                return;
            }
            const dest = parentOf(target.path) + "/" + name;
            run(["sh", "-c", "[ -e \"$2\" ] && exit 3; mv -- \"$1\" \"$2\"", "rename", target.path, dest], (code, err) => {
                if (code === 0) {
                    pendingSelect = name;
                    sfx.play("modal_close");
                } else {
                    sfx.play("error");
                    flash(code === 3 ? name + " already exists" : "rename failed: " + err.trim());
                }
            });
        } else if (dialog.mode === "goto") {
            const p = normalize(value.trim());
            run(["test", "-d", p], code => {
                if (code === 0)
                    go(p);
                else {
                    sfx.play("error");
                    flash("no such folder: " + p);
                }
            });
        } else if (dialog.mode === "mkdir") {
            const name = value.trim();
            if (!name || name.indexOf("/") >= 0) {
                sfx.play("error");
                return;
            }
            run(["mkdir", "--", dir + "/" + name], (code, err) => {
                if (code === 0) {
                    pendingSelect = name;
                    sfx.play("modal_close");
                } else {
                    sfx.play("error");
                    flash("couldn't create folder: " + err.trim());
                }
            });
        }
        mainFocus.forceActiveFocus();
    }

    function copyPath() {
        const p = current ? current.path : dir;
        run(["wl-copy", "--", p], code => flash(code === 0 ? "copied " + p : "wl-copy failed"));
        sfx.play("key");
    }

    // First terminal / file manager found wins; $TERMINAL is respected.
    function terminalHere() {
        sfx.play("launch");
        Quickshell.execDetached(["sh", "-c", "cd \"$1\" || exit 1; for t in \"$TERMINAL\" xdg-terminal-exec kitty foot alacritty wezterm ghostty konsole gnome-terminal xterm; do [ -n \"$t\" ] && command -v \"$t\" >/dev/null && exec \"$t\"; done", "ps2-browser", dir]);
    }

    function openInFileManager() {
        sfx.play("launch");
        Quickshell.execDetached(["sh", "-c", "for f in dolphin nautilus nemo thunar pcmanfm-qt pcmanfm caja; do command -v \"$f\" >/dev/null && exec \"$f\" \"$1\"; done; exec xdg-open \"$1\"", "ps2-browser", dir]);
    }

    // ---- sounds ----

    FileView {
        id: pluginSettingsFile
        path: app.configDir + "/plugin_settings.json"
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
        property var last: ({})
        function play(name) {
            if ((app.cfg.uiSounds ?? true) === false)
                return;
            const list = sfxPlayers.byName[name];
            if (!list || !list.length)
                return;
            const now = Date.now();
            if (now - (last[name] ?? 0) < 45)
                return;
            last[name] = now;
            const i = (sfxPlayers.next[name] ?? 0) % list.length;
            sfxPlayers.next[name] = i + 1;
            const p = list[i];
            if (p.playing)
                p.stop();
            p.play();
        }
    }

    Instantiator {
        id: sfxPlayers
        property var byName: ({})
        property var next: ({})
        readonly property var slots: ["navigate", "navigate", "navigate", "navigate", "launch", "popout_open", "popout_close", "modal_open", "modal_close", "error", "key", "key"]
        model: slots
        delegate: SoundEffect {
            required property string modelData
            source: Qt.resolvedUrl("sounds/" + modelData + ".wav")
            volume: Math.min(1, (app.cfg.volume ?? 100) / 100 * 0.8)
        }
        onObjectAdded: (index, object) => {
            const n = slots[index];
            const b = Object.assign({}, byName);
            b[n] = (b[n] ?? []).concat([object]);
            byName = b;
        }
    }

    // ---- window ----

    // Look of the console's Browser screen: black letterbox bars, a metallic grey
    // stage, the location in grey top-left and the selected item's name in yellow
    // top-right, cyan for the cursor, outlined text, button prompts in the bottom bar.
    readonly property color yellow: "#d6d40a"
    readonly property color cyan: "#38cefa"
    readonly property color outline: "#a0000000"

    FloatingWindow {
        id: win
        title: "PS2 Browser · " + app.dir
        implicitWidth: 1220
        implicitHeight: 780
        color: "#000000"
        visible: true
        onVisibleChanged: if (!visible)
            Qt.quit()

        Item {
            id: root
            anchors.fill: parent
            readonly property real barTop: 84
            readonly property real barBottom: 70

            // ---- stage ----
            Item {
                id: stage
                x: 0
                y: root.barTop
                width: root.width
                height: root.height - root.barTop - root.barBottom
                clip: true

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: "#a9a9a6"
                        }
                        GradientStop {
                            position: 0.45
                            color: "#76766f"
                        }
                        GradientStop {
                            position: 1.0
                            color: "#2f2f26"
                        }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: "#26ffffff"
                        }
                        GradientStop {
                            position: 0.45
                            color: "#00000000"
                        }
                        GradientStop {
                            position: 1.0
                            color: "#66000000"
                        }
                    }
                }

                // Soft light pooling at the upper left.
                Item {
                    id: lightPool
                    anchors.fill: parent
                    visible: false
                    Rectangle {
                        x: -parent.width * 0.15
                        y: -parent.height * 0.35
                        width: parent.width * 0.6
                        height: width
                        radius: width / 2
                        color: "#ffffff"
                        opacity: 0.22
                    }
                }
                MultiEffect {
                    anchors.fill: lightPool
                    source: lightPool
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 64
                }

                // A wisp of light drifting across the stage.
                Item {
                    id: wisp
                    property real t: 0
                    width: 1
                    height: 1
                    x: stage.width * (0.5 + 0.42 * Math.sin(t * 0.11)) 
                    y: stage.height * (0.5 + 0.38 * Math.sin(t * 0.17 + 1.3))
                    Timer {
                        interval: Qt.application.state === Qt.ApplicationActive ? 33 : 250
                        repeat: true
                        running: true
                        onTriggered: wisp.t = (Date.now() / 1000) % 3600
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 64
                        height: 64
                        radius: 32
                        color: "#ffffff"
                        opacity: 0.18
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blur: 1.0
                            blurMax: 32
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 9
                        height: 9
                        radius: 5
                        color: "#ffffff"
                    }
                }

                // Places
                Flickable {
                    x: 26
                    y: 22
                    width: 200
                    height: stage.height - 30
                    contentHeight: placesCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: placesCol
                        width: 200
                        spacing: 2
                        Repeater {
                            model: app.places
                            delegate: Item {
                                required property var modelData
                                required property int index
                                readonly property bool here: modelData.path === app.dir
                                readonly property bool cursor: app.placesFocused && app.placeIndex === index
                                width: 200
                                height: 34
                                Text {
                                    x: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: parent.cursor ? app.cyan : (parent.here ? app.yellow : (modelData.drive ? "#d8e4e4" : "#f0f0ee"))
                                    style: Text.Outline
                                    styleColor: app.outline
                                    font.family: "Rounded Mplus 1c"
                                    font.pixelSize: parent.here || parent.cursor ? 20 : 17
                                    font.weight: Font.Medium
                                    Behavior on font.pixelSize {
                                        NumberAnimation {
                                            duration: 160
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        app.placeIndex = index;
                                        app.go(modelData.path);
                                    }
                                }
                            }
                        }
                    }
                }

                // Details of the selection
                Column {
                    id: info
                    readonly property bool fits: root.width >= 1080
                    anchors.right: parent.right
                    anchors.rightMargin: 26
                    y: 24
                    width: 230
                    spacing: 7
                    visible: app.current !== null && fits
                    Repeater {
                        model: app.current ? [["type", Icons.label(app.current.isDir, app.current.suffix)], ["size", app.current.isDir ? "—" : Icons.humanSize(app.current.size)], ["modified", Qt.formatDateTime(app.current.modified, "yyyy/MM/dd  hh:mm")]] : []
                        delegate: Column {
                            required property var modelData
                            spacing: 1
                            Text {
                                text: modelData[0]
                                color: app.cyan
                                style: Text.Outline
                                styleColor: app.outline
                                font.family: "Rounded Mplus 1c"
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }
                            Text {
                                text: modelData[1]
                                color: "#ffffff"
                                style: Text.Outline
                                styleColor: app.outline
                                font.family: "Rounded Mplus 1c"
                                font.pixelSize: 17
                                bottomPadding: 8
                            }
                        }
                    }
                }

                GridView {
                    id: grid
                    property bool silent: false
                    x: 236
                    y: 4
                    width: stage.width - 236 - (info.fits ? 270 : 16)
                    height: stage.height - 8
                    cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 150)))
                    cellHeight: 190
                    clip: true
                    model: app.entries
                    currentIndex: -1
                    keyNavigationEnabled: false
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0
                    cacheBuffer: 600
                    onCurrentIndexChanged: if (!silent && currentIndex >= 0)
                        sfx.play("navigate")
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: grid.cellWidth
                        height: grid.cellHeight
                        Tile {
                            y: 14
                            anchors.horizontalCenter: parent.horizontalCenter
                            entry: parent.modelData
                            index: parent.index
                            home: app.home
                            selected: grid.currentIndex === parent.index && !app.placesFocused
                            onClicked: mouse => {
                                app.placesFocused = false;
                                grid.currentIndex = parent.index;
                                mainFocus.forceActiveFocus();
                                if (mouse.button === Qt.RightButton)
                                    ctx.openAt(mapToItem(root, mouse.x, mouse.y));
                            }
                            onDoubleClicked: app.openEntry(parent.modelData)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: app.entries.length === 0 && folder.status === FolderListModel.Ready
                        text: app.filter ? "Nothing matches \"" + app.filter + "\"." : "This folder is empty."
                        color: "#ffffff"
                        style: Text.Outline
                        styleColor: app.outline
                        font.family: "Rounded Mplus 1c"
                        font.pixelSize: 24
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        acceptedButtons: Qt.RightButton
                        onClicked: mouse => ctx.openAt(mapToItem(root, mouse.x, mouse.y))
                    }
                }
            }

            // ---- top bar: location left, selected name right ----
            Rectangle {
                width: root.width
                height: root.barTop
                color: "#000000"

                OrbGyro {
                    x: 6
                    y: 6
                    width: 84
                    height: 72
                }
                Column {
                    x: 92
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        text: app.dirName
                        color: "#c8c8c8"
                        font.family: "Rounded Mplus 1c"
                        font.pixelSize: 28
                        font.weight: Font.Medium
                    }
                    Text {
                        text: app.dir + (app.showHidden ? "   ·   hidden shown" : "") + "   ·   " + app.entries.length + (app.entries.length === 1 ? " item" : " items")
                        color: "#7a7a7a"
                        font.family: "Rounded Mplus 1c"
                        font.pixelSize: 13
                        width: root.width * 0.45
                        elide: Text.ElideMiddle
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 28
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.width * 0.42
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideMiddle
                    text: app.filtering || app.filter ? "Filter: " + app.filter + (app.filtering ? "▏" : "") : (app.current ? app.current.name : "")
                    color: app.filtering || app.filter ? app.cyan : app.yellow
                    font.family: "Rounded Mplus 1c"
                    font.pixelSize: 28
                    font.weight: Font.Medium
                }
            }

            // ---- bottom bar: prompts ----
            Rectangle {
                y: root.height - root.barBottom
                width: root.width
                height: root.barBottom
                color: "#000000"

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: -root.width * 0.12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 44
                    Repeater {
                        // Glyph colours nod to the four face-button colours.
                        model: [["⏎", "#8c8cff", "Enter"], ["⌫", "#ff5a5a", "Back"], ["⇥", "#4ad08c", "Places"], ["☰", "#ff7ad0", "Menu"]]
                        delegate: Row {
                            required property var modelData
                            spacing: 10
                            Text {
                                text: modelData[0]
                                color: modelData[1]
                                font.pixelSize: 22
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData[2]
                                color: "#d8d8d8"
                                font.family: "Rounded Mplus 1c"
                                font.pixelSize: 22
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: app.status !== "" ? app.status : "type to filter · f2 rename · del trash · ctrl+h hidden"
                    color: app.status !== "" ? app.cyan : "#6a6a6a"
                    font.family: "Rounded Mplus 1c"
                    font.pixelSize: 12
                    width: root.width * 0.26
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            // ---- context menu ----
            Rectangle {
                id: ctx
                visible: false
                z: 40
                width: 230
                height: ctxCol.implicitHeight + 12
                radius: 3
                color: "#f0101010"
                border.width: 1
                border.color: "#60ffffff"
                property var items: []
                function openAt(pt) {
                    const it = [];
                    if (app.current) {
                        it.push(["Open", () => app.openEntry(app.current)]);
                        it.push(["Rename", app.askRename]);
                        it.push(["Move to trash", app.askTrash]);
                        it.push(["Copy path", app.copyPath]);
                    }
                    it.push(["New folder", app.askNewFolder]);
                    it.push(["Terminal here", app.terminalHere]);
                    it.push(["Open in file manager", app.openInFileManager]);
                    it.push([app.showHidden ? "Hide hidden files" : "Show hidden files", () => app.showHidden = !app.showHidden]);
                    items = it;
                    x = Math.min(pt.x, root.width - width - 8);
                    y = Math.min(pt.y, root.height - height - 8);
                    visible = true;
                    sfx.play("popout_open");
                }
                Column {
                    id: ctxCol
                    x: 6
                    y: 6
                    width: parent.width - 12
                    Repeater {
                        model: ctx.items
                        delegate: Rectangle {
                            required property var modelData
                            width: ctxCol.width
                            height: 32
                            radius: 2
                            color: "transparent"
                            Text {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData[0]
                                color: ma.containsMouse ? app.cyan : "#e0e0e0"
                                font.family: "Rounded Mplus 1c"
                                font.pixelSize: 16
                            }
                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    ctx.visible = false;
                                    modelData[1]();
                                }
                            }
                        }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                z: 39
                visible: ctx.visible
                acceptedButtons: Qt.AllButtons
                onClicked: ctx.visible = false
            }

            GlassDialog {
                id: dialog
                property string mode: ""
                onAccepted: value => app.onDialogAccepted(value)
                onRejected: {
                    sfx.play("modal_close");
                    mainFocus.forceActiveFocus();
                }
            }

            Item {
                id: mainFocus
                focus: true
                Component.onCompleted: forceActiveFocus()
                Keys.onPressed: event => app.handleKey(event)
            }
        }
    }

    function moveSelection(delta) {
        if (entries.length === 0)
            return;
        const n = Math.max(0, Math.min(entries.length - 1, grid.currentIndex + delta));
        if (n === grid.currentIndex) {
            sfx.play("error");
            return;
        }
        grid.currentIndex = n;
        grid.positionViewAtIndex(n, GridView.Contain);
    }

    function handleKey(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const alt = event.modifiers & Qt.AltModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        const cols = Math.max(1, Math.floor(grid.width / grid.cellWidth));
        if (ctx.visible && event.key === Qt.Key_Escape) {
            ctx.visible = false;
            event.accepted = true;
            return;
        }
        if (placesFocused) {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                const n = Math.max(0, Math.min(places.length - 1, placeIndex + (event.key === Qt.Key_Up ? -1 : 1)));
                if (n !== placeIndex) {
                    placeIndex = n;
                    sfx.play("navigate");
                } else
                    sfx.play("error");
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
                placesFocused = false;
                go(places[placeIndex].path);
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Escape) {
                placesFocused = false;
                sfx.play("navigate");
            }
            event.accepted = true;
            return;
        }
        if (filtering) {
            if (event.key === Qt.Key_Escape) {
                filtering = false;
                filter = "";
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Backspace) {
                filter = filter.slice(0, -1);
                if (!filter)
                    filtering = false;
                sfx.play("key");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                filtering = false;
                if (entries.length === 1)
                    openEntry(entries[0]);
                event.accepted = true;
                return;
            }
        }
        event.accepted = true;
        switch (event.key) {
        case Qt.Key_Left:
            if (alt)
                goBack();
            else
                moveSelection(-1);
            return;
        case Qt.Key_Right:
            if (alt)
                goForward();
            else
                moveSelection(1);
            return;
        case Qt.Key_Up:
            if (alt)
                goUp();
            else
                moveSelection(-cols);
            return;
        case Qt.Key_Down:
            moveSelection(cols);
            return;
        case Qt.Key_PageUp:
            moveSelection(-cols * 3);
            return;
        case Qt.Key_PageDown:
            moveSelection(cols * 3);
            return;
        case Qt.Key_Home:
            moveSelection(-entries.length);
            return;
        case Qt.Key_End:
            moveSelection(entries.length);
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            openEntry(current);
            return;
        case Qt.Key_Backspace:
            goUp();
            return;
        case Qt.Key_Tab:
            {
                placesFocused = true;
                const here = places.findIndex(p => p.path === dir);
                placeIndex = here >= 0 ? here : 0;
                sfx.play("navigate");
                return;
            }
        case Qt.Key_Escape:
            if (filter) {
                filter = "";
                return;
            }
            Qt.quit();
            return;
        case Qt.Key_F2:
            askRename();
            return;
        case Qt.Key_Delete:
            askTrash();
            return;
        case Qt.Key_F5:
            rebuild.restart();
            return;
        case Qt.Key_Menu:
            ctx.openAt(Qt.point(grid.x + 40, grid.y + 40));
            return;
        }
        if (ctrl) {
            if (event.key === Qt.Key_H) {
                showHidden = !showHidden;
                sfx.play("key");
            } else if (event.key === Qt.Key_N && shift) {
                askNewFolder();
            } else if (event.key === Qt.Key_C) {
                copyPath();
            } else if (event.key === Qt.Key_T) {
                terminalHere();
            } else if (event.key === Qt.Key_E) {
                openInFileManager();
            } else if (event.key === Qt.Key_L) {
                askGoto();
            } else if (event.key === Qt.Key_Q || event.key === Qt.Key_W) {
                Qt.quit();
            } else if (event.key === Qt.Key_F) {
                filtering = true;
            }
            return;
        }
        // Type to filter.
        if (event.text && event.text.length === 1 && event.text >= " " && !alt) {
            filtering = true;
            filter += event.text;
            sfx.play("key");
            return;
        }
        event.accepted = false;
    }

    function askGoto() {
        sfx.play("modal_open");
        dialog.mode = "goto";
        dialog.open("Go to", "", dir, true, "go");
    }

    // Test hook: PS2_BROWSER_SHOT=/path.png renders one frame to a file and quits.
    Timer {
        running: app.shotPath !== ""
        interval: 2500
        onTriggered: root.grabToImage(r => {
            r.saveToFile(app.shotPath);
            Qt.quit();
        })
    }
}
