pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin

// "Show desktop" that KWin can animate.
//
// KWin's built-in Show Desktop (Workspace::setShowingDesktop) hides windows
// without going through the minimize animation, so no effect - including Magic
// Lamp - ever runs for it. Minimizing the windows instead does run the
// minimize effect, and with Magic Lamp enabled that is the genie.
//
// The action is stateless on purpose: if any candidate window is still visible
// it minimizes all of them, otherwise it unminimizes all of them. That keeps a
// second press restoring the desktop no matter who minimized the windows in
// between, and lets other code trigger it without having to track state.
//
// The action is named "Genie Show Desktop". Its default sequence is set here,
// but KGlobalAccel gives a stored value in kglobalshortcutsrc precedence over
// the sequence default, so the installer also writes the shortcut explicitly
// through setForeignShortcut (and clears Meta+D from KWin's native
// "Show Desktop" action, which this replaces).

Item {
    id: root

    // Never touched: our own layer-shell surfaces, the desktop shell and
    // screen-share bridges all look like ordinary windows to KWin, and
    // minimizing them would blank the panel or the desktop.
    readonly property var ignoredClasses: [
        "quickshell",
        "plasmashell",
        "org.kde.plasmashell",
        "xwaylandvideobridge",
        "waylandvideobridge",
        "ksmserver",
        "krunner",
        "org.kde.polkit-kde-agent",
        "org.kde.kglobalaccel"
    ]

    function isCandidate(w) {
        if (!w || w.deleted)
            return false;
        if (w.specialWindow || w.desktopWindow || w.popupWindow)
            return false;
        if (w.skipTaskbar)
            return false;
        return ignoredClasses.indexOf(String(w.resourceClass).toLowerCase()) < 0;
    }

    function toggle() {
        const wins = Workspace.windows.filter(w => isCandidate(w));
        // Only the windows on the desktop we are looking at: minimizing
        // invisible windows on other desktops would surprise nobody nicely.
        const here = wins.filter(w => w.desktops.includes(Workspace.currentDesktop));
        const showing = here.every(w => w.minimized);
        for (let i = 0; i < here.length; i++)
            here[i].minimized = showing ? false : true;
        console.warn("genieshowdesktop:", showing ? "restoring" : "minimizing", here.length, "window(s)");
    }

    ShortcutHandler {
        name: "Genie Show Desktop"
        text: "Show the desktop, minimizing windows with the genie animation"
        sequence: "Meta+D"
        onActivated: root.toggle()
    }

    Component.onCompleted: console.warn("genieshowdesktop: script started");
}
