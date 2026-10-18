pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

// The icon of a FileEntry.
//
// Three looks, as in the fork:
//   - an application shortcut (or an entry whose icon the user picked) is drawn
//     on a Material You tile, tinted when Material You icons are on;
//   - a plain file or folder with no icon of its own becomes a single Material
//     Symbols glyph in the palette colour, with no tile;
//   - anything else is the full-colour image, clipped to a rounded square when
//     the icon was chosen from an ordinary picture.
//
// The bundled monochrome set only covers applications it has a matching name
// for, so an image that cannot be loaded falls back to the system icon theme.
Item {
    id: root

    required property var entry
    property bool materialYou: false
    property bool vibrant: false
    property bool rounded: DesktopLayout.roundIcons
    property bool failed: false

    readonly property alias status: image.status

    // Only the set's own glyphs (currentColor, i.e. black) need tinting to read;
    // they appear solely off the tile. Artwork on a tile is an application logo
    // or a user-picked picture and keeps its colours.
    readonly property bool tinted: materialYou && !root.failed && !root.onTile

    // An application shortcut, or an entry whose icon the user picked, gets the
    // Material You tile. Everything else is either a glyph or a bare image.
    // Decided here rather than in FileEntry so a broken binding there cannot
    // silently drop the tile: Material You puts every application, and any
    // entry the user gave an icon to, on a coloured tile.
    readonly property bool onTile: root.materialYou && ((root.entry?.isDesktopFile ?? false) || ((root.entry?.override?.icon ?? "") !== ""))
    readonly property bool glyph: (root.entry?.useMonoFileIcon ?? false) && !root.failed

    readonly property color tileColour: {
        const c = Colours.palette.m3primaryContainer;
        if (!root.vibrant)
            return c;
        return Qt.hsla(c.hslHue, Math.min(1, c.hslSaturation * 1.35),
            Math.max(0.2, Math.min(0.42, c.hslLightness + 0.03)), c.a);
    }
    readonly property color glyphColour: Colours.palette.m3onPrimaryContainer


    onEntryChanged: root.failed = false

    onMaterialYouChanged: root.failed = false

    Rectangle {
        id: tile

        anchors.fill: parent
        radius: width * 0.28
        visible: root.onTile
        color: root.tileColour
    }

    Image {
        id: image

        anchors.fill: parent
        anchors.margins: root.onTile ? Math.round(parent.width * 0.16) : 0
        source: !root.entry ? "" : root.failed ? root.entry.fallbackIconSource() : root.entry.iconSource(root.materialYou)
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: !root.glyph && !clip.active
        layer.enabled: root.tinted
        layer.effect: Colouriser {
            sourceColor: "black"
            // The set draws currentColor, which resolves to black here, and the
            // colouriser turns it into a visible glyph: on the tile it has to
            // contrast with the tile itself, off the tile it takes the primary
            // colour as upstream does.
            colorizationColor: root.onTile ? root.glyphColour : Colours.palette.m3primary
        }

        onStatusChanged: {
            if (status === Image.Error && root.materialYou && !root.failed)
                root.failed = true;
        }
    }

    // Tinted icons are glyphs, so only full-colour icons get the corners.
    Loader {
        id: clip

        anchors.fill: parent
        active: root.rounded && !root.tinted && image.status === Image.Ready

        sourceComponent: MultiEffect {
            source: image
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }

    Rectangle {
        id: mask

        anchors.fill: parent
        radius: width * 0.24
        visible: false
        layer.enabled: true
        layer.smooth: true
    }

    // Material Symbols default to the outlined cut, which is too thin to read on
    // a wallpaper: use the filled one. MaterialIcon builds its own font (family
    // plus variable axes) and assigning font.pixelSize broke that binding, so
    // the size comes from the token only.
    MaterialIcon {
        anchors.centerIn: parent
        width: Math.round(parent.width * 0.62)
        height: width
        visible: root.glyph
        text: root.entry?.monoFileGlyph ?? ""
        color: root.glyphColour
        fontStyle: Tokens.font.icon.extraLarge
        fill: 1
    }
}
