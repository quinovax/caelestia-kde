pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

// One file in ~/Desktop: its metadata, what to show for it and how to open it.
Scope {
    id: root

    required property string fileName
    required property string filePath
    required property bool fileIsDir
    required property string fileSuffix
    required property var fileModified
    required property var fileSize

    readonly property string key: DesktopLayout.fileKey(fileName)
    readonly property string path: filePath.replace("file://", "")
    readonly property string url: "file://" + path.split("/").map(encodeURIComponent).join("/")
    readonly property bool isDesktopFile: fileName.toLowerCase().endsWith(".desktop")
    readonly property string kind: fileIsDir ? "dir" : "file"
    // Rough type for "Sort by type": launchers together, then by extension.
    readonly property string typeName: isDesktopFile ? " application" : fileIsDir ? "" : fileSuffix.toLowerCase()

    property string desktopName: ""
    // The Name key the label was read from, e.g. "Name[zh_CN]".
    property string desktopNameKey: "Name"
    property bool desktopNameFound: false
    property string desktopIcon: ""
    property var desktopCategories: []

    /// User overrides live next to the shortcut, not in the .desktop file:
    /// desktop shortcuts are often symlinks into a root-owned directory.
    readonly property var override: ShortcutOverrides.forPath(path)

    /// A shortcut to a shell script opens in a terminal instead of being handed
    /// to xdg-open. The link target is checked too: a shortcut is often a
    /// symlink without the extension (e.g. "HMCL" -> "HMCL-3.17.0.357.sh").
    /// Material You icons are a per-screen setting, as they were in the fork.
    /// A FileEntry is created by an Instantiator and does not know its screen, so
    /// this reads the global default, which is what a single-screen desktop and
    /// any screen without an override uses.
    readonly property bool materialYouIcons: GlobalConfig.background.materialYouIconsEnabled
    /// Whether this entry is drawn on the Material You tile, the way an
    /// application is: applications always, and any entry whose icon the user
    /// picked in the details dialog.
    readonly property bool usesTile: materialYouIcons && (isDesktopFile || ((override?.icon ?? "") !== ""))

    /// Material You mode for folders and files with no icon of their own: just
    /// the shape, in the palette colour and without an application style tile.
    /// An icon chosen in the details dialog wins over the default glyph.
    readonly property bool useMonoFileIcon: materialYouIcons && !isDesktopFile && ((override?.icon ?? "") === "")

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

    /// A custom icon is far more often an ordinary picture (screenshot, photo,
    /// cover art) than a shaped logo, so it is clipped to a rounded square before
    /// being drawn. Icons given by name come from the icon theme and are left
    /// alone.
    readonly property bool roundCustomIcon: (override?.icon ?? "").startsWith("/")

    readonly property bool isShellScript: {
        if (fileIsDir)
            return false;
        return [fileName, filePath].some(n => /\.(sh|bash|zsh)$/i.test(n ?? ""));
    }

    readonly property string displayName: {
        const custom = override?.name ?? "";
        if (custom !== "")
            return custom;
        if (!isDesktopFile)
            return fileName;
        if (desktopNameFound)
            return desktopName;
        return desktopEntry?.name || fileName.slice(0, -8);
    }

    readonly property DesktopEntry desktopEntry: {
        if (!isDesktopFile)
            return null;
        const cleanId = fileName.slice(0, -8);
        return DesktopEntries.applications.values.find(e => e.id === fileName || e.id === cleanId || e.id + ".desktop" === fileName)
            ?? DesktopEntries.heuristicLookup(cleanId)
            ?? null;
    }

    readonly property var categories: desktopCategories.length > 0 ? desktopCategories : (desktopEntry?.categories ?? [])

    readonly property string iconName: {
        const custom = override?.icon ?? "";
        if (custom !== "")
            return custom;
        if (fileIsDir)
            return "folder";
        if (isDesktopFile)
            return desktopIcon || desktopEntry?.icon || "application-x-executable";
        const ext = fileSuffix.toLowerCase();
        if (ext === "pdf")
            return "application-pdf";
        if (["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp"].includes(ext))
            return "image-x-generic";
        if (["mp4", "mkv", "webm", "avi", "mov"].includes(ext))
            return "video-x-generic";
        if (["zip", "tar", "gz", "rar", "7z"].includes(ext))
            return "package-x-generic";
        if (["mp3", "wav", "flac", "ogg"].includes(ext))
            return "audio-x-generic";
        if (["qml", "js", "html", "css", "py", "sh", "cpp", "c", "h", "json"].includes(ext))
            return "text-x-script";
        return "text-x-generic";
    }

    // Launcher icon name or absolute path, empty for plain files.
    // Launcher icon name or absolute path, empty for plain files. A user-set icon
    // wins, and is treated like any other icon below: a path stays a path, a name
    // is resolved through the icon theme.
    readonly property string appIcon: {
        const custom = override?.icon ?? "";
        if (custom !== "")
            return custom;
        return isDesktopFile ? (desktopEntry?.icon || desktopIcon) : "";
    }

    /// Where to find the tile's image.
    ///
    /// The Material You look is the bundled monochrome set, but it only covers
    /// the applications that ship with a matching name. Anything it does not
    /// have (a distro package, a Chinese app, an AppImage) has to fall back to
    /// the system icon theme rather than render a blank tile.
    function iconSource(materialYou: bool): string {
        const setBase = Qt.resolvedUrl(Quickshell.shellDir + "/assets/icons/yet-another-monochrome-icon-set");
        if (appIcon !== "") {
            if (appIcon.startsWith("/"))
                return "file://" + appIcon;
            // An application keeps its own full-colour artwork even in Material
            // You mode, exactly as the fork did: the tile behind it is tinted, the
            // icon is not. The monochrome set only replaces plain file and folder
            // glyphs, never an application's logo.
            return Quickshell.iconPath(appIcon, "application-x-executable");
        }
        if (materialYou) {
            if (fileIsDir)
                return setBase + "/places/scalable/folder.svg";
            return setBase + "/mimetypes/scalable/" + iconName + ".svg";
        }
        return "image://icon/" + iconName;
    }

    /// Image used when the one iconSource names cannot be loaded: the same
    /// icon name through the theme, and if the theme has nothing either, the
    /// generic text document icon that every icon theme ships. Without this the
    /// tile stays blank until the set is updated.
    function fallbackIconSource(): string {
        const themed = Quickshell.iconPath(iconName);
        if (themed !== "")
            return "image://icon/" + iconName;
        return "image://icon/text-x-generic";
    }


    function launch(): void {
        // A user-given command wins: the details dialog can point a shortcut at
        // something other than the file it sits on.
        const custom = override?.exec ?? "";
        if (custom !== "") {
            Launch.exec(custom.split(" "));
            return;
        }
        // Shell scripts are watched rather than run silently: they run in the
        // shell's own terminal tab, which keeps the output visible. Without that
        // tab, fall back to the external terminal.
        if (isShellScript) {
            const runner = `${Quickshell.shellDir}/assets/run_script_in_terminal.sh`;
            Launch.exec([...GlobalConfig.general.apps.terminal, runner, path]);
            return;
        }
        // Run the launcher file itself: its name need not match an installed app id,
        // and xdg-open would open it in an editor instead.
        if (isDesktopFile)
            Launch.exec(["gio", "launch", path]);
        else
            Launch.exec(["xdg-open", path]);
    }

    // Opens files with this launcher, as when they are dropped onto it.
    function launchWith(paths: var): void {
        if (isDesktopFile)
            Launch.exec(["gio", "launch", path, ...paths]);
    }

    function reloadDesktopFile(): void {
        desktopFile.reload();
    }

    FileView {
        id: desktopFile

        path: root.isDesktopFile ? root.path : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            // Prefer Name[lang_COUNTRY], then Name[lang], then Name, as the spec says.
            const locale = Qt.locale().name;
            const nameKeys = [`Name[${locale}]`, `Name[${locale.split("_")[0]}]`, "Name"];
            const values = {};
            let inDesktopEntry = false;
            for (const raw of text().split("\n")) {
                const line = raw.trim();
                if (line.startsWith("[")) {
                    inDesktopEntry = line === "[Desktop Entry]";
                    continue;
                }
                const eq = line.indexOf("=");
                if (!inDesktopEntry || eq < 0)
                    continue;
                const key = line.substring(0, eq).trim();
                if (!(key in values))
                    values[key] = line.substring(eq + 1).trim();
            }
            const nameKey = nameKeys.find(k => values[k]);
            root.desktopNameFound = !!nameKey;
            if (nameKey) {
                root.desktopName = values[nameKey];
                root.desktopNameKey = nameKey;
            }
            root.desktopIcon = values["Icon"] ?? "";
            root.desktopCategories = (values["Categories"] ?? "").split(";").filter(c => c.length > 0);
        }
    }
}
