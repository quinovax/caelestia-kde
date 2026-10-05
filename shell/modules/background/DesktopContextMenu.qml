pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components.controls as Controls
import qs.services
import qs.utils
import qs.modules.nexus

Controls.Menu {
    id: root

    property real _menuW: root.backgroundItem && root.backgroundItem.implicitWidth > 0 ? root.backgroundItem.implicitWidth : 250
    property real _menuH: root.backgroundItem && root.backgroundItem.implicitHeight > 0 ? root.backgroundItem.implicitHeight : 350
    property bool _flipX: attachTo && attachTo.parent && (attachTo.x + _menuW > attachTo.parent.width)
    property bool _flipY: attachTo && attachTo.parent && (attachTo.y + _menuH > attachTo.parent.height)
    property string screenName: ""
    property var itemPool: ({})
    property var entryByKey: ({})
    property real perfMenuOpenStartedAt: 0

    function executeEntryByKey(key) {
        let entry = root.entryByKey[key];
        if (!entry) return;

        root.expanded = false;

        execTimer.pendingAction = () => {
            if (entry.action) {
                if (entry.action === "Wallpapers.next()") Wallpapers.next();
                else if (entry.action === "Quickshell.reload()") Quickshell.reload();
                else if (entry.action === "WindowFactory.create()") WindowFactory.create();
                else if (entry.action === "ToggleDesktopIcons") {
                    let newState = !GlobalConfig.background.desktopIconsEnabled;
                    GlobalConfig.background.desktopIconsEnabled = newState;
                    for (let i = 0; i < Quickshell.screens.length; i++) {
                        let sConf = GlobalConfig.forScreen(Quickshell.screens[i].name);
                        if (sConf) sConf.background.resetOption("desktopIconsEnabled");
                    }
                    GlobalConfig.save();
                } else if (entry.action === "OpenRightClickMenu") {
                    WindowFactory.create(null, {
                        initialPageIdx: PageRegistry.indexForKey("desktop"),
                        initialSubPageIdx: 2
                    });
                } else if (entry.action === "OpenTerminal") {
                    Launch.exec([...GlobalConfig.general.apps.terminal]);
                } else if (entry.action === "AddShortcutMenu") {
                    // handled by the second level menu
                } else if (entry.action === "AddAppShortcut") {
                    Launch.exec(["caelestia-add-shortcut", "app"]);
                } else if (entry.action === "AddFolderShortcut") {
                    Launch.exec(["caelestia-add-shortcut", "folder"]);
                } else if (entry.action === "AddFileShortcut") {
                    Launch.exec(["caelestia-add-shortcut", "file"]);
                    // Pick a file or folder and drop a shortcut onto the desktop.
                    // .desktop files are copied (launchers); anything else becomes
                    // a symlink, which works for both files and folders.
                    const script = [
                        'P=$(kdialog --title "Add file/folder shortcut" --getopenfilename "$HOME/" 2>/dev/null)',
                        '[ -n "$P" ] || P=$(zenity --title "Add file/folder shortcut" --file-selection 2>/dev/null)',
                        '[ -n "$P" ] || exit 0',
                        'DESK=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")',
                        'case "$P" in',
                        '  *.desktop) cp "$P" "$DESK/" && chmod +x "$DESK/$(basename "$P")" ;;',
                        '  *) ln -sfn "$P" "$DESK/$(basename "$P")" ;;',
                        'esac'
                    ].join("; ");
                    Launch.exec(["sh", "-c", script]);
                }
            } else if (entry.command) {
                if (entry.command === "terminal") {
                    Launch.exec([...GlobalConfig.general.apps.terminal]);
                } else {
                    Launch.exec(typeof entry.command === "string" ? entry.command.split(" ") : entry.command);
                }
            }
        };
        execTimer.restart();
    }

    function buildAddShortcutSubmenu() {
        function entry(text, icon, action) {
            const it = menuItemComp.createObject(root);
            it.text = text;
            it.icon = icon;
            it.clicked.connect(() => root.executeAction(action));
            return it;
        }

        return [
            entry(qsTr("Application..."), "apps", "AddAppShortcut"),
            entry(qsTr("File..."), "insert_drive_file", "AddFileShortcut"),
            entry(qsTr("Folder..."), "folder", "AddFolderShortcut")
        ];
    }

    function executeAction(action) {
        const key = "__action_" + action;
        root.entryByKey[key] = { action: action };
        root.executeEntryByKey(key);
        delete root.entryByKey[key];
    }

    function applyEntries(entries, sourceName) {
        const buildStartedAt = Date.now();
        const normalized = (!entries || entries.length === 0)
            ? ContextMenuStore.cloneEntries(ContextMenuStore.defaultEntries())
            : ContextMenuStore.cloneEntries(entries);
        const newArr = [];
        const nextEntryByKey = {};

        for (let i = 0; i < normalized.length; i++) {
            let entry = normalized[i];
            if (!entry.enabled) continue;

            let key = (entry.id && entry.id.length > 0) ? entry.id : ("idx_" + i);
            nextEntryByKey[key] = entry;

            let item = root.itemPool[key];
            if (!item) {
                item = menuItemComp.createObject(root);
                item.clicked.connect(() => root.executeEntryByKey(key));
                root.itemPool[key] = item;
            }

            item.text = entry.label;
            item.icon = entry.icon || "application-x-executable";
            // "Add a shortcut" fans out into app / file / folder.
            item.children = entry.action === "AddShortcutMenu" ? root.buildAddShortcutSubmenu() : [];
            newArr.push(item);
        }
        for (const k in root.itemPool) {
            if (!nextEntryByKey.hasOwnProperty(k)) {
                root.itemPool[k].destroy();
                delete root.itemPool[k];
            }
        }

        root.entryByKey = nextEntryByKey;
        root.dynamicModel = newArr;
        const buildMs = Date.now() - buildStartedAt;
        console.log("[perf][DesktopContextMenu] build model source=" + sourceName + " items=" + newArr.length + " ms=" + buildMs);

        if (root.perfMenuOpenStartedAt > 0) {
            const openMs = Date.now() - root.perfMenuOpenStartedAt;
            console.log("[perf][DesktopContextMenu] open latency ms=" + openMs + " source=" + sourceName);
            root.perfMenuOpenStartedAt = 0;
        }
    }

    function reloadMenu(forceDisk) {
        ContextMenuStore.ensureLoaded(forceDisk === true);
        if (ContextMenuStore.loaded && !ContextMenuStore.loading) {
            root.applyEntries(ContextMenuStore.entries, forceDisk === true ? "store_disk" : "store_cache");
        }
    }

    attachSideX: _flipX ? Controls.Menu.Left : Controls.Menu.Right
    attachSideY: _flipY ? Controls.Menu.Top : Controls.Menu.Bottom
    thisSideX: _flipX ? Controls.Menu.Right : Controls.Menu.Left
    thisSideY: _flipY ? Controls.Menu.Bottom : Controls.Menu.Top
    transparentBackground: true

    rightClickReposition: true
    onRightClickedAt: (x, y) => ContextMenuStore.openDesktopContextMenu(x, y, root.screenName)

    onExpandedChanged: {
        if (expanded) {
            root.perfMenuOpenStartedAt = Date.now();
            reloadMenu(false);
        }
    }

    Component.onCompleted: reloadMenu(true)

    Timer {
        id: execTimer

        property var pendingAction: null

        interval: 250
        repeat: false

        onTriggered: {
            if (pendingAction) pendingAction();
            pendingAction = null;
        }
    }

    Connections {
        function onEntriesChanged() {
            root.applyEntries(ContextMenuStore.entries, "store_update");
        }

        target: ContextMenuStore
    }

    Component {
        id: menuItemComp

        Controls.MenuItem {}
    }
}
