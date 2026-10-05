pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// Per-shortcut customisations for the desktop: display name, icon and the
/// command a shortcut launches.
///
/// These deliberately live in this file instead of being written into the
/// .desktop file: shortcuts on the desktop are often symlinks into
/// /usr/share/applications or a Flatpak export owned by root, so writing them
/// fails (PermissionError) and rewriting them silently turns the link into a
/// copy that no longer follows the installed app.
Singleton {
    id: root

    readonly property string storePath: Quickshell.env("HOME") + "/.local/share/caelestia/desktop-shortcuts.json"

    /// { "<absolute shortcut path>": { name, icon, exec } }
    property var overrides: ({})
    property bool loaded: false
    property bool writeQueued: false

    signal changed

    function forPath(path: string): var {
        return root.overrides[path] ?? null;
    }

    function nameFor(path: string): string {
        return root.forPath(path)?.name ?? "";
    }

    function iconFor(path: string): string {
        return root.forPath(path)?.icon ?? "";
    }

    function execFor(path: string): string {
        return root.forPath(path)?.exec ?? "";
    }

    function set(path: string, key: string, value: string): void {
        if (path.length === 0)
            return;
        const next = Object.assign({}, root.overrides);
        const entry = Object.assign({}, next[path] ?? {});
        if (value.length === 0)
            delete entry[key];
        else
            entry[key] = value;
        if (Object.keys(entry).length === 0)
            delete next[path];
        else
            next[path] = entry;
        root.overrides = next;
        root.save();
        root.changed();
    }

    /// Forget everything customised for a shortcut (used when it is deleted).
    function clear(path: string): void {
        if (path.length === 0 || !(path in root.overrides))
            return;
        const next = Object.assign({}, root.overrides);
        delete next[path];
        root.overrides = next;
        root.save();
        root.changed();
    }

    function save(): void {        writeProc.jsonContent = JSON.stringify(root.overrides);
        writeProc.running = true;
    }

    Process {
        id: readProc

        command: ["sh", "-c", "cat \"" + root.storePath + "\" 2>/dev/null || echo '{}'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim().length > 0 ? text : "{}");
                    root.overrides = parsed && typeof parsed === "object" ? parsed : ({});
                } catch (e) {
                    console.warn("[ShortcutOverrides] unreadable store:", e);
                    root.overrides = ({});
                }
                root.loaded = true;
            }
        }
    }

    Process {
        id: writeProc

        property string jsonContent: "{}"

        command: [
            "python3", "-c",
            "import sys, os; p=sys.argv[1]; d=os.path.dirname(p); os.makedirs(d, exist_ok=True) if d else None; open(p, 'w').write(sys.argv[2])",
            root.storePath, jsonContent
        ]
    }

    Component.onCompleted: readProc.running = true
}
