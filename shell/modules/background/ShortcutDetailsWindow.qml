pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

/// Details dialog for a desktop shortcut: icon, type, source, and user
/// attributes, with the ability to rename it, change its icon, or delete it
/// (also with the Delete key).
///
/// The window is built on demand and destroyed as soon as it closes.
/// A FloatingWindow is a real toplevel, so when the compositor closes it (the
/// window close shortcut, a decoration button, the task manager, ...) that
/// close writes `visible = false` from C++, which wipes any `visible: ...`
/// binding. The window then stayed invisible forever and could never be opened
/// again. Rebuilding it on every open sidesteps the whole problem.
Scope {
    id: scope

    LazyLoader {
        id: loader

        active: ShortcutDetails.open

        FloatingWindow {
            id: root

            readonly property var details: ShortcutDetails
            readonly property bool isApp: details.kind === "application"

            function kindLabel(): string {
                if (details.kind === "application")
                    return qsTr("Application shortcut");
                if (details.kind === "folder")
                    return qsTr("Folder link");
                return qsTr("File link");
            }

            color: Colours.tPalette.m3surface
            title: qsTr("Shortcut details")
            implicitWidth: 460
            implicitHeight: column.implicitHeight + Tokens.padding.extraLarge * 2

            // Tokens/Config are per-screen singletons and have to be told which
            // screen the window lives on (same as StyledWindow does).
            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            function syncFields(): void {
                const override = ShortcutOverrides.forPath(details.path) ?? {};
                nameField.text = override.name ?? (details.isApp ? details.entryName : details.fileName);
                iconField.text = override.icon ?? details.entryIcon;
                execField.text = override.exec ?? details.entryExec;
            }

            /// The dialog exists to rename the shortcut, so the caret belongs in
            /// the name field. Focus is retried once the surface is really
            /// mapped, otherwise the input method stays on the old window.
            function focusName(): void {
                Qt.callLater(() => {
                    nameField.forceActiveFocus();
                    nameField.selectAll();
                });
            }

            Component.onCompleted: {
                syncFields();
                focusName();
            }

            onVisibleChanged: {
                if (!visible) {
                    // Closed from the outside. Nothing can bring this surface
                    // back, so let the loader drop it.
                    details.close();
                    return;
                }
                syncFields();
                focusName();
            }

            // The dialog can be reused for another shortcut without being closed.
            Connections {
                function onPathChanged(): void {
                    syncFields();
                }

                target: details
            }

            Connections {
                function onPicked(field: string, value: string): void {
                    if (field === "icon")
                        iconField.text = value;
                    else if (field === "command")
                        execField.text = value;
                }

                target: details
            }

            Shortcut {
                sequence: "Delete"
                enabled: root.visible
                onActivated: details.trash()
            }

            StyledRect {
                anchors.fill: parent
                color: Colours.tPalette.m3surface
                radius: Tokens.rounding.extraLarge

                ColumnLayout {
                    id: column

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.padding.extraLarge
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.large

                        Image {
                            // implicitWidth/Height are read-only inside a Layout.
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 64
                            source: details.iconSource
                            sourceSize.width: 64
                            sourceSize.height: 64
                            fillMode: Image.PreserveAspectFit
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.extraSmall

                            StyledText {
                                Layout.fillWidth: true
                                text: details.isApp ? (details.entryName || details.fileName) : details.fileName
                                font: Tokens.font.title.small
                                color: Colours.palette.m3onSurface
                                elide: Text.ElideMiddle
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.kindLabel()
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: infoColumn.implicitHeight + Tokens.padding.medium * 2
                        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 1)
                        radius: Tokens.rounding.large

                        ColumnLayout {
                            id: infoColumn

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            Repeater {
                                model: {
                                    const rows = [
                                        { label: qsTr("Location"), value: details.path },
                                        { label: qsTr("Executable"), value: details.executable ? qsTr("Yes") : qsTr("No") }
                                    ];
                                    if (details.linkTarget.length > 0)
                                        rows.unshift({ label: qsTr("Points to"), value: details.linkTarget });
                                    if (details.entryExec.length > 0)
                                        rows.push({ label: qsTr("Command"), value: details.entryExec });
                                    if (details.entryComment.length > 0)
                                        rows.push({ label: qsTr("Comment"), value: details.entryComment });
                                    return rows;
                                }

                                RowLayout {
                                    id: infoRow

                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.medium

                                    StyledText {
                                        Layout.preferredWidth: 90
                                        text: infoRow.modelData.label
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurfaceVariant
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: infoRow.modelData.value
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurface
                                        elide: Text.ElideMiddle
                                        wrapMode: Text.NoWrap
                                    }
                                }
                            }
                        }
                    }

                    StyledTextField {
                        id: nameField

                        Layout.fillWidth: true
                        placeholderText: qsTr("Name")
                        supportingText: qsTr("Shortcut name")
                        onAccepted: details.rename(root.cleanedName())
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        StyledTextField {
                            id: iconField

                            Layout.fillWidth: true
                            placeholderText: qsTr("Icon")
                            supportingText: qsTr("Icon name or absolute path")
                        }

                        IconButton {
                            Layout.alignment: Qt.AlignTop
                            icon: "folder_open"
                            onClicked: details.pick("icon")
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.isApp
                        spacing: Tokens.spacing.small

                        StyledTextField {
                            id: execField

                            Layout.fillWidth: true
                            placeholderText: qsTr("Command")
                            supportingText: qsTr("Command the shortcut runs")
                        }

                        IconButton {
                            Layout.alignment: Qt.AlignTop
                            icon: "folder_open"
                            onClicked: details.pick("command")
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: details.errorText.length > 0
                        text: details.errorText
                        font: Tokens.font.body.small
                        color: Colours.palette.m3error
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        IconTextButton {
                            Layout.fillWidth: true
                            icon: "check"
                            text: qsTr("Save")
                            onClicked: {
                                const name = root.cleanedName();
                                if (name.length > 0)
                                    details.rename(name);
                                details.setIcon(iconField.text);
                                if (root.isApp)
                                    details.setExec(execField.text);
                            }
                        }

                        IconTextButton {
                            Layout.fillWidth: true
                            icon: "delete"
                            text: qsTr("Move to Trash")
                            inactiveColour: Colours.palette.m3errorContainer
                            inactiveOnColour: Colours.palette.m3onErrorContainer
                            onClicked: details.trash()
                        }

                        IconTextButton {
                            Layout.fillWidth: true
                            icon: "close"
                            text: qsTr("Close")
                            onClicked: details.close()
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Tip: press Delete to move the shortcut to the trash")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }

            /// The edited name. Application shortcuts keep showing their own name
            /// (no ".desktop" suffix), only file/folder links carry an extension.
            function cleanedName(): string {
                return nameField.text.trim();
            }
        }
    }

    // Lets the dialog be opened from the command line, which makes it easy to
    // test without right-clicking:
    //   qs -c caelestia ipc call shortcut details /path/to/x.desktop
    IpcHandler {
        target: "shortcut"

        function details(path: string): void {
            ShortcutDetails.show({
                path: path,
                fileName: path.substring(path.lastIndexOf("/") + 1),
                kind: path.endsWith(".desktop") ? "application" : "file",
                executable: path.endsWith(".desktop")
            });
        }
    }
}
