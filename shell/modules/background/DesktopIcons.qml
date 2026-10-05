pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property ShellScreen screenData

    property int cellWidth: 100
    property int cellHeight: 120

    property var savedOrder: []
    property bool layoutLoaded: false
    // True while an icon's inline rename editor is open; the background window
    // raises its layer-shell keyboard focus on this so the editor can type.
    property Item renamingDelegate: null

    readonly property bool renameActive: renamingDelegate !== null

    function getIconCols(): int {
        return Math.max(1, Math.floor(gridItem.width / root.cellWidth));
    }

    function getIconRows(): int {
        return Math.max(1, Math.floor(gridItem.height / root.cellHeight));
    }

    function saveLayout(): void {
        if (!layoutLoaded)
            return;
        let arr = [];
        for (let i = 0; i < instantiator.count; i++) {
            let item = instantiator.objectAt(i);
            if (item)
                arr.push({ name: item.fileName, col: item.col, row: item.row });
        }
        saveProc.jsonContent = JSON.stringify(arr);
        saveProc.running = true;
    }

    function isCellFree(c: int, r: int, ignoreItem: Item): bool {
        for (let i = 0; i < instantiator.count; i++) {
            let item = instantiator.objectAt(i);
            if (item && item !== ignoreItem && item.col === c && item.row === r)
                return false;
        }
        return true;
    }

    function findFreeCell(): var {
        for (let r = 0; r < 1000; r++) {
            for (let c = 0; c < getIconCols(); c++) {
                if (isCellFree(c, r, null))
                    return { col: c, row: r };
            }
        }
        return { col: 0, row: 0 };
    }

    function runFileOp(args: var): void {
        fileOpProc.commandLine = args;
        fileOpProc.running = true;
    }

    function trashIcon(path: string): void {
        if (path.length === 0)
            return;
        runFileOp(["kioclient", "move", path, "trash:/"]);
    }

    function renameIcon(oldPath: string, newName: string): void {
        const trimmed = newName.trim();
        if (trimmed.length === 0)
            return;
        if (trimmed === "." || trimmed === ".." || trimmed.includes("/"))
            return;

        if (oldPath.toLowerCase().endsWith(".desktop")) {
            // Shortcuts show a name of their own, and the file itself is often a
            // symlink into a root owned directory, so the custom name is kept in
            // the overrides store instead of being written into the file.
            ShortcutOverrides.set(oldPath, "name", trimmed);
            return;
        }

        const idx = Math.max(oldPath.lastIndexOf("/"), 0);
        const dir = oldPath.substring(0, idx);
        if (trimmed === oldPath.substring(idx + 1))
            return;
        runFileOp(["kioclient", "move", oldPath, dir + "/" + trimmed]);
    }

    /// Re-read every delegate (used after a rename, so the new label shows up
    /// without waiting for the desktop model to change).
    function reloadAllInfo(): void {
        for (let i = 0; i < instantiator.count; i++)
            reloadInfo(instantiator.objectAt(i));
    }

    /// Re-read everything that is parsed out of a shortcut file.
    function reloadInfo(item: var): void {
        if (!item)
            return;
        if (item.isDesktopFile) {
            item.desktopIcon = "";
            item.desktopComment = "";
            item.desktopExec = "";
            item.desktopType = "";
        } else {
            item.desktopLinkTarget = "";
        }
        item.reloadFromFile();
    }

    function showDetails(item: var): void {
        if (!item)
            return;
        ShortcutDetails.show({
            path: item.path,
            fileName: item.fileName,
            kind: item.isDesktopFile ? "application" : (item.fileIsDir ? "folder" : "file"),
            linkTarget: item.desktopLinkTarget !== item.path ? item.desktopLinkTarget : "",
            executable: item.isDesktopFile ? true : item.desktopExecutable,
            iconSource: item.getIconSource(item.fileIsDir, item.fileName, item.fileSuffix),
            entryName: item.desktopName,
            entryIcon: item.desktopIcon,
            entryComment: item.desktopComment,
            entryExec: item.desktopExec,
            entryType: item.desktopType
        });
    }

    function iconAt(x: real, y: real): bool {
        if (!visible)
            return false;
        const c = Math.floor((x - gridItem.x) / root.cellWidth);
        const r = Math.floor((y - gridItem.y) / root.cellHeight);
        for (let i = 0; i < instantiator.count; i++) {
            const item = instantiator.objectAt(i);
            if (item && item.col === c && item.row === r)
                return true;
        }
        return false;
    }

    anchors.fill: parent
    visible: GlobalConfig.forScreen(screenData.name).background.enabled && GlobalConfig.forScreen(screenData.name).background.wallpaperEnabled && GlobalConfig.forScreen(screenData.name).background.desktopIconsEnabled

    Component.onCompleted: {
        loadLayoutProc.running = true;
    }

    Process {
        id: loadLayoutProc

        command: ["sh", "-c", "cat ~/.local/share/caelestia/desktop_layout.json 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.savedOrder = JSON.parse(text);
                } catch (e) {
                    root.savedOrder = [];
                }
                root.layoutLoaded = true;
                for (var i = 0; i < instantiator.count; i++) {
                    var item = instantiator.objectAt(i);
                    if (item)
                        item.initPosition();
                }
            }
        }
    }

    Process {
        id: saveProc

        property string jsonContent: ""

        command: ["python3", "-c", "import sys, os; d = os.path.dirname(sys.argv[1]); os.makedirs(d, exist_ok=True) if d else None; open(sys.argv[1], 'w').write(sys.argv[2])", Quickshell.env("HOME") + "/.local/share/caelestia/desktop_layout.json", jsonContent]
    }

    Process {
        id: fileOpProc

        property var commandLine: []
        property string errorText: ""

        command: commandLine
        stderr: StdioCollector {
            onStreamFinished: fileOpProc.errorText = text.trim()
        }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                Toaster.toast(qsTr("File operation failed"),
                    fileOpProc.errorText.length > 0 ? fileOpProc.errorText : qsTr("kioclient could not complete the request"),
                    "error");
            else
                root.reloadAllInfo();
            fileOpProc.errorText = "";
        }
    }

    Item {
        id: gridItem

        readonly property int barZone: Visibilities.bars.get(root.screenData.name)?.visualThickness ?? (Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness))
        readonly property int baseMargin: Tokens.padding.large * 2

        anchors.fill: parent
        anchors.margins: baseMargin
        anchors.leftMargin: Config.bar.position === "left" ? baseMargin + barZone : baseMargin
        anchors.rightMargin: Config.bar.position === "right" ? baseMargin + barZone : baseMargin
        anchors.topMargin: Config.bar.position === "top" ? baseMargin + barZone : baseMargin
        anchors.bottomMargin: Config.bar.position === "bottom" ? baseMargin + barZone : baseMargin

        Instantiator {
            id: instantiator

            model: FolderListModel {
                id: folderModel

                folder: "file://" + Quickshell.env("HOME") + "/Desktop"
                showDirsFirst: true
                nameFilters: ["*"]
            }

            // Respect XDG: the desktop folder is not always $HOME/Desktop
            // (e.g. zh_CN setups use ~/桌面 until xdg dirs are migrated).
            Process {
                command: ["sh", "-c", "xdg-user-dir DESKTOP 2>/dev/null || echo \"$HOME/Desktop\""]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const dir = text.trim();
                        if (dir.length > 0)
                            folderModel.folder = "file://" + dir;
                    }
                }
            }
            onObjectAdded: (index, object) => {
                object.parent = gridItem;
            }

            delegate: Item {
                id: delegateItem

                required property string fileName
                required property string filePath
                required property bool fileIsDir
                required property string fileSuffix

                /// FolderListModel hands out percent-encoded URLs, so a shortcut
                /// named e.g. "微信.desktop" arrived as "%E5%BE%AE..." and every
                /// shell command using it (cat/kioclient/xdg-open) failed.
                property string path: {
                    const p = filePath.replace("file://", "");
                    try {
                        return decodeURIComponent(p);
                    } catch (e) {
                        return p;
                    }
                }
                property string desktopName: fileName
                property string desktopIcon: ""
                property string desktopComment: ""
                property string desktopExec: ""
                property string desktopType: ""
                property string desktopLinkTarget: ""
                property bool desktopExecutable: false
                property int col: -1
                property int row: -1
                property bool renaming: false

                readonly property bool isDesktopFile: fileName.toLowerCase().endsWith(".desktop")

                /// Name / icon / command customised through the details dialog.
                readonly property var override: ShortcutOverrides.overrides[path] ?? null

                /// True when the details dialog gave this entry an icon of its
                /// own (any kind: application, file or folder).
                readonly property bool hasCustomIcon: (override?.icon ?? "") !== ""
                // Only the base name is edited: ".desktop" is an implementation
                // detail of the shortcut and would otherwise eat the whole
                // 100px-wide editor ("xxx.desktop" only ever showed "esktop").
                readonly property string renameBase: isDesktopFile ? fileName.slice(0, -8) : fileName

                readonly property DesktopEntry desktopEntry: {
                    if (!fileName.toLowerCase().endsWith(".desktop"))
                        return null;
                    const cleanId = fileName.endsWith(".desktop") ? fileName.slice(0, -8) : fileName;
                    return DesktopEntries.applications.values.find(e => e.id === fileName || e.id === cleanId || e.id + ".desktop" === fileName)
                        ?? DesktopEntries.heuristicLookup(cleanId)
                        ?? null;
                }

                property bool useMaterialYouIcons: GlobalConfig.forScreen(screenData.name).background.materialYouIconsEnabled
                property bool useVibrantIcons: GlobalConfig.forScreen(screenData.name).background.materialYouIconsVibrant

                /// Icon name/path as declared by the shortcut. An absolute path
                /// from the shortcut itself wins: amber/ACE packages (WeChat, QQ)
                /// register a bare name like "wechat" with the icon theme, but the
                /// shortcut points straight at their real artwork.
                readonly property string rawIconValue: {
                    if (!isDesktopFile)
                        return "";
                    const entryIcon = desktopEntry?.icon ?? "";
                    if (desktopIcon.startsWith("/"))
                        return desktopIcon;
                    if (entryIcon.startsWith("/"))
                        return entryIcon;
                    return entryIcon || desktopIcon;
                }


                /// Rounded container behind the glyph, plus the glyph colour.
                /// The palette's primary is tone 90 (nearly white), so tinting
                /// with it washed the icons out; "vibrant" used to force
                /// saturation to 1.0 and turned them neon. The container/on
                /// pair is what Material uses for themed icons.
                readonly property color iconContainerColour: {
                    const c = Colours.palette.m3primaryContainer;
                    if (!useVibrantIcons)
                        return c;
                    return Qt.hsla(c.hslHue, Math.min(1, c.hslSaturation * 1.35),
                        Math.max(0.2, Math.min(0.42, c.hslLightness + 0.03)), c.a);
                }
                readonly property color iconGlyphColour: Colours.palette.m3onPrimaryContainer

                function startRename(): void {
                    if (root.renamingDelegate && root.renamingDelegate !== delegateItem)
                        root.renamingDelegate.cancelRename();
                    root.renamingDelegate = delegateItem;
                    renaming = true;
                    // Pre-fill the name shown on the desktop, which for a
                    // shortcut is its Name key rather than the file name.
                    renameField.text = isDesktopFile ? (desktopName || renameBase) : fileName;
                    renameField.selectAll();
                    renameField.forceActiveFocus();
                }

                function commitRename(): void {
                    if (!renaming)
                        return;
                    const target = renameField.text.trim();
                    renaming = false;
                    if (root.renamingDelegate === delegateItem)
                        root.renamingDelegate = null;
                    // Shortcuts keep their file name; renameIcon() rewrites the
                    // Name key of the .desktop file instead, so the label on the
                    // desktop changes. File/folder links really are renamed.
                    root.renameIcon(path, target);
                }

                function cancelRename(): void {
                    renaming = false;
                    if (root.renamingDelegate === delegateItem)
                        root.renamingDelegate = null;
                }

                function initPosition(): void {
                    if (col !== -1 && row !== -1)
                        return;

                    let targetCol = -1;
                    let targetRow = -1;
                    let foundSaved = false;
                    for (let i = 0; i < root.savedOrder.length; i++) {
                        if (root.savedOrder[i].name === fileName) {
                            targetCol = root.savedOrder[i].col;
                            targetRow = root.savedOrder[i].row;
                            foundSaved = true;
                            break;
                        }
                    }

                    if (foundSaved && root.isCellFree(targetCol, targetRow, delegateItem)) {
                        col = targetCol;
                        row = targetRow;
                    } else {
                        let freeCell = root.findFreeCell();
                        col = freeCell.col;
                        row = freeCell.row;
                        root.saveLayout();
                    }
                }

                function getIconName(isDir: bool, filename: string, suffix: string): string {
                    if (isDir)
                        return "folder";
                    const ext = suffix.toLowerCase();
                    const imageExts = ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp"];
                    const videoExts = ["mp4", "mkv", "webm", "avi", "mov"];
                    const archiveExts = ["zip", "tar", "gz", "rar", "7z"];
                    const audioExts = ["mp3", "wav", "flac", "ogg"];
                    const codeExts = ["qml", "js", "html", "css", "py", "sh", "cpp", "c", "h", "json"];

                    if (ext === "pdf")
                        return "application-pdf";
                    if (filename.toLowerCase().endsWith(".desktop"))
                        return desktopIcon || desktopEntry?.icon || "application-x-executable";
                    if (imageExts.includes(ext))
                        return "image-x-generic";
                    if (videoExts.includes(ext))
                        return "video-x-generic";
                    if (archiveExts.includes(ext))
                        return "package-x-generic";
                    if (audioExts.includes(ext))
                        return "audio-x-generic";
                    if (codeExts.includes(ext))
                        return "text-x-script";

                    return "text-x-generic";
                }

                /// Full-colour artwork for this entry (an override wins).
                function getIconSource(isDir: bool, filename: string, suffix: string): string {
                    const custom = override?.icon ?? "";
                    if (custom !== "") {
                        if (custom.startsWith("/"))
                            return "file://" + custom;
                        return Quickshell.iconPath(custom, "application-x-executable");
                    }
                    if (isDesktopFile && rawIconValue !== "") {
                        if (rawIconValue.startsWith("/"))
                            return "file://" + rawIconValue;
                        return Quickshell.iconPath(rawIconValue, "application-x-executable");
                    }
                    return "image://icon/" + getIconName(isDir, filename, suffix);
                }

                /// Material You mode for folders and files with no icon of their
                /// own: just the shape, in the palette colour and without an
                /// application style tile. An icon chosen in the details dialog
                /// wins over the default glyph.
                readonly property bool useMonoFileIcon: useMaterialYouIcons && !isDesktopFile && !hasCustomIcon

                /// Whether this entry is drawn on the Material You tile (the way
                /// application shortcuts are): applications always, and any
                /// entry with a custom icon.
                readonly property bool usesTile: useMaterialYouIcons && (isDesktopFile || hasCustomIcon)

                /// Material Symbols glyph for this entry (M3 icon language).
                readonly property string monoFileGlyph: {
                    if (fileIsDir)
                        return "folder";
                    const ext = fileSuffix.toLowerCase();
                    const groups = {
                        image: ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "avif"],
                        movie: ["mp4", "mkv", "webm", "avi", "mov", "m4v"],
                        music_note: ["mp3", "wav", "flac", "ogg", "m4a", "opus"],
                        folder_zip: ["zip", "tar", "gz", "xz", "rar", "7z", "zst"],
                        picture_as_pdf: ["pdf"],
                        description: ["txt", "md", "log", "json", "yml", "yaml", "toml", "ini", "conf"],
                        code: ["qml", "js", "mjs", "ts", "py", "sh", "c", "h", "cpp", "hpp", "rs", "go", "java", "css", "html"]
                    };
                    for (const glyph in groups) {
                        if (groups[glyph].includes(ext))
                            return glyph;
                    }
                    return "draft";
                }

                /// Parse the Name / Icon / Comment / Exec / Type keys of a
                /// .desktop file. Kept as a plain function so it runs on the
                /// whole file text.
                function parseDesktopFile(content: string): void {
                    if (!content)
                        return;
                    const lines = content.split("\n");
                    let inEntry = false;
                    let plainName = "";
                    let localisedName = "";
                    let icon = "";
                    let comment = "";
                    let exec = "";
                    let type = "";

                    // Values are taken after the "=" instead of with a hard coded
                    // offset: "Name[zh_CN]=" is 12 characters, not 13, and the
                    // off-by-one silently ate the first character of every
                    // localised name (Bazaar -> "azaar", 星火应用商店 -> "火应用商店").
                    function valueOf(line: string): string {
                        return line.substring(line.indexOf("=") + 1);
                    }

                    for (let i = 0; i < lines.length; i++) {
                        const line = lines[i].trim();
                        if (line === "[Desktop Entry]") {
                            inEntry = true;
                            continue;
                        }
                        if (line.startsWith("[")) {
                            inEntry = false;
                            continue;
                        }
                        if (!inEntry || line.length === 0)
                            continue;

                        if (line.startsWith("Name[zh_CN]="))
                            localisedName = valueOf(line);
                        else if (line.startsWith("Name="))
                            plainName = valueOf(line);
                        else if (line.startsWith("Icon="))
                            icon = valueOf(line);
                        else if (line.startsWith("Comment[zh_CN]="))
                            comment = valueOf(line);
                        else if (line.startsWith("Comment=") && comment === "")
                            comment = valueOf(line);
                        else if (line.startsWith("Exec="))
                            exec = valueOf(line);
                        else if (line.startsWith("Type="))
                            type = valueOf(line);
                    }

                    desktopName = localisedName !== "" ? localisedName : (plainName !== "" ? plainName : fileName);
                    desktopIcon = icon;
                    desktopComment = comment;
                    desktopExec = exec;
                    desktopType = type;
                }

                function launch(): void {
                    const custom = override?.exec ?? "";
                    if (custom !== "") {
                        Launch.exec(custom.split(" "));
                        return;
                    }
                    if (delegateItem.desktopEntry)
                        Launch.launchEntry(delegateItem.desktopEntry);
                    else
                        Launch.exec(["xdg-open", path]);
                }

                width: root.cellWidth
                height: root.cellHeight
                x: col * root.cellWidth + (dragHandler.active ? dragHandler.translation.x : 0)
                y: row * root.cellHeight + (dragHandler.active ? dragHandler.translation.y : 0)
                z: dragHandler.active ? 10 : 1

                function reloadFromFile(): void {
                    if (isDesktopFile)
                        parseDesktopFile(desktopFile.text());
                    else
                        desktopMetaProc.running = true;
                }

                Component.onCompleted: {
                    if (root.layoutLoaded)
                        initPosition();
                    desktopName = fileName;
                    root.reloadInfo(delegateItem);
                }

                Connections {
                    function onSaved(): void {
                        if (ShortcutDetails.path === delegateItem.path)
                            root.reloadInfo(delegateItem);
                    }

                    target: ShortcutDetails
                }

                Component.onDestruction: {
                    if (root.renamingDelegate === delegateItem)
                        root.renamingDelegate = null;
                }

                // The Instantiator recycles delegates when the desktop model
                // changes, so everything parsed from the file has to be redone
                // for the new file - otherwise a recycled delegate keeps showing
                // the previous shortcut's icon and name.
                onPathChanged: root.reloadInfo(delegateItem)

                Process {
                    id: desktopMetaProc

                    // readlink -f: where a file/folder shortcut points, and
                    // whether the target is executable.
                    command: ["sh", "-c", "readlink -f -- \"$1\"; if [ -x \"$1\" ]; then echo yes; else echo no; fi", "--", path]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            // Only trust a complete two-line answer; a partial
                            // chunk would give a mangled path.
                            if (!text.endsWith("\n"))
                                return;
                            const lines = text.trim().split("\n");
                            if (lines.length > 0)
                                delegateItem.desktopLinkTarget = lines[0];
                            if (lines.length > 1)
                                delegateItem.desktopExecutable = lines[1] === "yes";
                        }
                    }
                }


                // Read the shortcut with FileView instead of shelling out to
                // `cat`: StdioCollector hands out chunks, and with a chunk
                // boundary in the middle of a UTF-8 name the label lost its
                // first character ("Bazaar" -> "azaar", "微信" -> "信").
                FileView {
                    id: desktopFile

                    path: delegateItem.isDesktopFile ? delegateItem.path : ""
                    printErrors: false
                    watchChanges: true
                    onLoaded: delegateItem.parseDesktopFile(text())
                    onTextChanged: delegateItem.parseDesktopFile(text())
                }


                Rectangle {
                    anchors.fill: parent
                    color: Colours.palette.m3onSurface
                    opacity: mouseArea.containsMouse || dragHandler.active ? 0.12 : 0
                    radius: Tokens.rounding.medium

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 100
                        }
                    }
                }

                // Icon on its own, so the label and the rename editor are not
                // competing with it inside a layout (a ColumnLayout gave the
                // label a width of 0, which clipped names that used to fit).
                Item {
                    id: iconArea

                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64
                    height: 64
                    anchors.topMargin: Tokens.padding.small

                    Rectangle {
                        id: iconTile

                        anchors.centerIn: parent
                        width: 64
                        height: 64
                        radius: 20
                        visible: delegateItem.usesTile
                        color: delegateItem.iconContainerColour
                    }

                    Image {
                        id: iconImage

                        anchors.centerIn: parent
                        width: delegateItem.usesTile ? Math.round(iconTile.width * 0.72) : 64
                        height: width
                        source: delegateItem.getIconSource(delegateItem.fileIsDir, delegateItem.fileName, delegateItem.fileSuffix)
                        fillMode: Image.PreserveAspectFit
                        visible: !delegateItem.useMonoFileIcon
                    }

                    MaterialIcon {
                        id: iconMono

                        anchors.centerIn: parent
                        visible: delegateItem.useMonoFileIcon
                        text: delegateItem.monoFileGlyph
                        color: delegateItem.iconGlyphColour
                        // MaterialIcon builds its own font (family + variable
                        // axes); assigning font.pixelSize broke that binding and
                        // the glyph names were rendered as literal text.
                        fontStyle: Tokens.font.icon.extraLarge
                        // Material Symbols default to the outlined cut, which is
                        // too thin to read on a wallpaper: use the filled one.
                        fill: 1
                    }
                }

                // Label: a fixed box the size of the cell, centred, two lines
                // max. Long names elide, names that fit are shown in full.
                Text {
                    id: labelText
                    visible: !delegateItem.renaming
                    anchors.top: iconArea.bottom
                    anchors.topMargin: Tokens.spacing.extraSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.cellWidth - Tokens.spacing.extraSmall
                    text: delegateItem.override?.name
                        ?? (delegateItem.isDesktopFile
                            ? (delegateItem.desktopName || delegateItem.desktopEntry?.name || delegateItem.fileName)
                            : delegateItem.fileName)
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.small
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    lineHeight: Math.ceil(font.pixelSize * 1.3)
                    lineHeightMode: Text.FixedHeight
                    verticalAlignment: Text.AlignTop
                    elide: Text.ElideRight
                    style: Text.Outline
                    styleColor: Colours.palette.m3surface
                }

                // Rename editor: its own floating box under the icon (and wider
                // than the cell so longer names are visible while typing). The
                // icon area stays outside it, so a click meant for the editor
                // can never launch the application.
                StyledRect {
                    id: renameBox

                    visible: delegateItem.renaming
                    z: 20
                    anchors.top: iconArea.bottom
                    anchors.topMargin: Tokens.spacing.extraSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.cellWidth + Tokens.spacing.large
                    height: Math.max(renameField.implicitHeight + Tokens.padding.extraSmall * 2, 28)
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3primaryContainer

                    TextInput {
                        id: renameField

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.small
                        anchors.rightMargin: Tokens.padding.small

                        clip: true
                        selectByMouse: true
                        selectionColor: Colours.palette.m3primary
                        selectedTextColor: Colours.palette.m3onPrimary
                        color: Colours.palette.m3onPrimaryContainer
                        font: Tokens.font.body.small
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter

                        onAccepted: delegateItem.commitRename()
                        onActiveFocusChanged: {
                            // Clicking anywhere outside the editor cancels the rename.
                            if (!activeFocus && delegateItem.renaming)
                                delegateItem.cancelRename();
                        }
                        Keys.onEscapePressed: delegateItem.cancelRename()
                    }
                }

                DragHandler {
                    id: dragHandler

                    property real lastTranslationX: 0
                    property real lastTranslationY: 0

                    target: null
                    enabled: !delegateItem.renaming
                    onTranslationChanged: {
                        if (active) {
                            lastTranslationX = translation.x;
                            lastTranslationY = translation.y;
                        }
                    }
                    onActiveChanged: {
                        if (!active) {
                            let dropX = col * root.cellWidth + lastTranslationX + delegateItem.width / 2;
                            let dropY = row * root.cellHeight + lastTranslationY + delegateItem.height / 2;
                            let newCol = Math.floor(dropX / root.cellWidth);
                            let newRow = Math.floor(dropY / root.cellHeight);

                            newCol = Math.max(0, Math.min(newCol, root.getIconCols() - 1));
                            newRow = Math.max(0, Math.min(newRow, root.getIconRows() - 1));

                            if (!root.isCellFree(newCol, newRow, delegateItem)) {
                                // Find nearest free cell outwards using a spiral or simple fallback
                                let found = false;
                                for (let rad = 1; rad < Math.max(root.getIconCols(), root.getIconRows()); rad++) {
                                    for (let r = Math.max(0, newRow - rad); r <= Math.min(root.getIconRows() - 1, newRow + rad); r++) {
                                        for (let c = Math.max(0, newCol - rad); c <= Math.min(root.getIconCols() - 1, newCol + rad); c++) {
                                            if (root.isCellFree(c, r, delegateItem)) {
                                                newCol = c;
                                                newRow = r;
                                                found = true;
                                                break;
                                            }
                                        }
                                        if (found)
                                            break;
                                    }
                                    if (found)
                                        break;
                                }
                            }

                            col = newCol;
                            row = newRow;
                            root.saveLayout();
                        }
                    }
                }

                MouseArea {
                    id: mouseArea

                    anchors.fill: parent
                    // While the editor is open its clicks belong to the text
                    // field, not to the icon underneath.
                    enabled: !delegateItem.renaming
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            // The click that dismisses the editor should not
                            // immediately open a new menu on the same icon.
                            if (!delegateItem.renaming)
                                iconMenu.openFor(delegateItem, mouse.x, mouse.y);
                            return;
                        }
                        if (delegateItem.renaming) {
                            renameField.forceActiveFocus();
                            return;
                        }
                        if (root.renameActive) {
                            // Another icon's editor is open: click outside it
                            // cancels the rename instead of opening the file.
                            root.renamingDelegate.cancelRename();
                            return;
                        }
                        delegateItem.launch();
                    }
                }
            }
        }
    }

    DesktopIconContextMenu {
        id: iconMenu

        onRenameRequested: (delegateTarget) => {
            if (delegateTarget)
                delegateTarget.startRename();
        }
        onTrashRequested: path => root.trashIcon(path)
        onDetailsRequested: delegateTarget => root.showDetails(delegateTarget)
    }
}
