pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

/// Details dialog for a desktop shortcut: icon, type, source, and user
/// attributes, with the ability to rename it, change its icon, or delete it
/// (also with the Delete key).
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
    visible: details.open

    onVisibleChanged: {
        if (visible) {
            nameField.text = details.isApp ? (details.entryName || details.fileName) : details.fileName;
            iconField.text = details.entryIcon;
            root.forceActiveFocus();
        }
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

            StyledTextField {
                id: iconField

                Layout.fillWidth: true
                visible: root.isApp
                placeholderText: qsTr("Icon")
                supportingText: qsTr("Icon name or absolute path")
                onAccepted: details.setIcon(iconField.text)
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
                        // For a shortcut this renames the displayed name, for a
                        // file/folder link it renames the link itself.
                        const name = root.cleanedName();
                        if (name.length > 0)
                            details.rename(name);
                        if (root.isApp)
                            details.setIcon(iconField.text);
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
