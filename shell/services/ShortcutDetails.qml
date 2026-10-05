pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia

/// State and file operations behind the desktop shortcut details dialog.
Singleton {
    id: root

    property bool open: false

    /// Absolute path of the shortcut on the desktop.
    property string path: ""
    property string fileName: ""
    /// "application" | "file" | "folder"
    property string kind: "file"
    property string linkTarget: ""
    property bool executable: false
    property string iconSource: ""

    /// .desktop specific values, editable in the dialog.
    property string entryName: ""
    property string entryIcon: ""
    property string entryComment: ""
    property string entryExec: ""
    property string entryType: ""

    property string errorText: ""

    signal saved

    /// Emitted with the field ("icon"/"command") and the chosen path.
    signal picked(string field, string value)

    function show(info: var): void {
        root.errorText = "";
        root.path = info.path ?? "";
        root.fileName = info.fileName ?? "";
        root.kind = info.kind ?? "file";
        root.linkTarget = info.linkTarget ?? "";
        root.executable = info.executable ?? false;
        root.iconSource = info.iconSource ?? "";
        root.entryName = info.entryName ?? "";
        root.entryIcon = info.entryIcon ?? "";
        root.entryComment = info.entryComment ?? "";
        root.entryExec = info.entryExec ?? "";
        root.entryType = info.entryType ?? "";
        root.open = true;
    }

    function close(): void {
        root.open = false;
    }

    function runProc(args: var): void {
        opProc.command = args;
        opProc.running = true;
    }

    /// Customisations live in ShortcutOverrides instead of inside the .desktop
    /// file: desktop shortcuts are frequently symlinks into root owned
    /// directories, so editing them fails.
    function rename(newName: string): void {
        const trimmed = (newName ?? "").trim();
        if (trimmed.length === 0) {
            root.errorText = qsTr("Invalid name");
            return;
        }
        ShortcutOverrides.set(root.path, "name", trimmed);
        root.entryName = trimmed;
        root.saved();
    }

    /// The icon the desktop shows for this shortcut, whatever its kind.
    function setIcon(newIcon: string): void {
        const trimmed = (newIcon ?? "").trim();
        ShortcutOverrides.set(root.path, "icon", trimmed);
        root.entryIcon = trimmed;
        root.saved();
    }

    /// The command an application shortcut launches.
    function setExec(newExec: string): void {
        const trimmed = (newExec ?? "").trim();
        ShortcutOverrides.set(root.path, "exec", trimmed);
        root.entryExec = trimmed;
        root.saved();
    }

    /// Open a file dialog and hand the result back to the dialog.
    function pick(kind: string): void {
        pickProc.pendingField = kind;
        pickProc.command = ["caelestia-pick-path", kind];
        pickProc.running = true;
    }

    /// Move the shortcut to the trash and close the dialog.
    function trash(): void {
        if (root.path.length === 0)
            return;
        trashProc.command = ["kioclient", "move", root.path, "trash:/"];
        trashProc.running = true;
    }

    Process {
        id: trashProc

        onExited: (exitCode) => {
            if (exitCode !== 0) {
                root.errorText = qsTr("Operation failed");
                return;
            }
            ShortcutOverrides.clear(root.path);
            Toaster.toast(qsTr("Moved to trash"), root.fileName, "delete");
            root.close();
        }
    }

    Process {
        id: pickProc

        property string pendingField: ""

        stdout: StdioCollector {
            onStreamFinished: {
                const picked = text.trim();
                if (picked.length > 0)
                    root.picked(pickProc.pendingField, picked);
            }
        }
    }

    Process {
        id: opProc

        property string errorOutput: ""

        stderr: StdioCollector {
            onStreamFinished: opProc.errorOutput = text.trim()
        }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                root.errorText = opProc.errorOutput.length > 0 ? opProc.errorOutput : qsTr("Operation failed");
            else
                root.saved();
            opProc.errorOutput = "";
        }
    }
}
