pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

// The icon of a FileEntry, laid out exactly as the fork drew it:
//   - an application shortcut or an entry with a user-picked icon sits on a
//     Material You tile at 72% of the tile, keeping its own colours;
//   - a plain file or folder with no icon of its own is a filled Material
//     Symbols glyph in the palette's on-container colour;
//   - a user-picked picture is clipped to a rounded square.
//
// There is deliberately no colouriser over the artwork: the fork never tinted
// application icons, and doing so is what flattened QQ, WeChat and bilibili
// to one colour.
Item {
    id: root

    required property var entry
    property bool materialYou: false
    property bool vibrant: false
    property bool rounded: DesktopLayout.roundIcons
    property bool failed: false

    readonly property alias status: image.status

    // Fork predicates, computed here from the entry so a stale binding in
    // FileEntry cannot silently drop the tile.
    readonly property bool hasCustomIcon: (root.entry?.override?.icon ?? "") !== ""
    readonly property bool usesTile: root.materialYou && ((root.entry?.isDesktopFile ?? false) || root.hasCustomIcon)
    readonly property bool useMonoFileIcon: root.materialYou && !(root.entry?.isDesktopFile ?? false) && !root.hasCustomIcon
    readonly property bool roundCustomIcon: (root.entry?.override?.icon ?? "").startsWith("/")

    readonly property color tileColour: {
        const c = Colours.palette.m3primaryContainer;
        if (!root.vibrant)
            return c;
        return Qt.hsla(c.hslHue, Math.min(1, c.hslSaturation * 1.35),
            Math.max(0.2, Math.min(0.42, c.hslLightness + 0.03)), c.a);
    }
    readonly property color glyphColour: Colours.palette.m3onPrimaryContainer

    onEntryChanged: {
        root.failed = false;
        root.diag();
    }
    onMaterialYouChanged: root.failed = false

    // Fork: iconArea is a 64x64 box; the tile fills it and the image sits
    // centred at 72% when on the tile. Here the box is whatever the caller
    // sized us to, so the same ratios apply.
    Rectangle {
        id: tile

        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        radius: Math.round(width * 20 / 64)
        visible: root.usesTile
        color: root.tileColour
    }

    Image {
        id: image

        anchors.centerIn: parent
        width: root.usesTile ? Math.round(tile.width * 0.72) : parent.width
        height: width
        source: !root.entry ? "" : root.failed ? root.entry.fallbackIconSource() : root.entry.iconSource(root.materialYou)
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: !root.useMonoFileIcon

        onStatusChanged: {
            if (status === Image.Error && root.materialYou && !root.failed)
                root.failed = true;
        }
    }

    // Rounded square used to clip a custom icon. It has to be a layered item
    // of its own: MultiEffect samples the mask texture in the source item's
    // coordinates, so it must have the same size as the image it masks.
    Item {
        id: customIconMask

        anchors.fill: image
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: Math.round(width * 0.28)
            color: "white"
        }
    }

    Loader {
        id: clip

        anchors.fill: image
        active: root.roundCustomIcon && root.rounded && image.status === Image.Ready

        sourceComponent: MultiEffect {
            source: image
            maskEnabled: true
            maskSource: customIconMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }

    // Material Symbols default to the outlined cut, which is too thin to read
    // on a wallpaper: use the filled one. MaterialIcon builds its own font
    // (family plus variable axes); assigning font.pixelSize breaks that.
    MaterialIcon {
        anchors.centerIn: parent
        visible: root.useMonoFileIcon
        text: root.entry?.monoFileGlyph ?? ""
        color: root.glyphColour
        fontStyle: Tokens.font.icon.extraLarge
        fill: 1
    }
}