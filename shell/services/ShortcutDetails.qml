pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

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

    /// Rename the shortcut itself (the file name on the desktop).
    function rename(newName: string): void {
        const trimmed = (newName ?? "").trim();
        if (trimmed.length === 0 || trimmed === root.fileName)
            return;
        if (trimmed === "." || trimmed === ".." || trimmed.includes("/")) {
            root.errorText = qsTr("Invalid name");
            return;
        }
        const idx = Math.max(root.path.lastIndexOf("/"), 0);
        const dir = root.path.substring(0, idx);
        root.runProc(["kioclient", "move", root.path, dir + "/" + trimmed]);
        root.fileName = trimmed;
    }

    /// Change the Icon= key of a .desktop shortcut.
    function setIcon(newIcon: string): void {
        const trimmed = (newIcon ?? "").trim();
        if (root.kind !== "application" || trimmed.length === 0 || trimmed === root.entryIcon)
            return;
        const script = [
            "import sys",
            "p, icon = sys.argv[1], sys.argv[2]",
            "lines = open(p, encoding='utf-8').read().splitlines()",
            "out, done = [], False",
            "for line in lines:",
            "    if not done and line.startswith('Icon='):",
            "        out.append('Icon=' + icon)",
            "        done = True",
            "    else:",
            "        out.append(line)",
            "if not done:",
            "    out.append('Icon=' + icon)",
            "open(p, 'w', encoding='utf-8').write('\\n'.join(out) + '\\n')"
        ].join("\n");
        root.runProc(["python3", "-c", script, root.path, trimmed]);
        root.entryIcon = trimmed;
    }

    function trash(): void {
        if (root.path.length === 0)
            return;
        root.runProc(["kioclient", "move", root.path, "trash:/"]);
        root.open = false;
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
