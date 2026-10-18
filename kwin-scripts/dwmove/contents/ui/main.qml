pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin

// Dynamic virtual desktops for KWin (Plasma 6).
//
// - Meta+PgDown: switch to the next *normal* desktop (skips caelestia's
//   "special:*" desktops); past the last one, a new desktop is created and
//   switched to.
// - Meta+PgUp: switch to the previous normal desktop (clamped at the first).
// - Meta+Shift+PgDown / PgUp: move *every* window of the current desktop to
//   the next / previous one (and follow them there).
// - Meta+Ctrl+PgDown / PgUp: move only the focused window.
// - Recycling: normal desktops with no windows are removed, keeping at most
//   one empty desktop. special:* desktops are never touched.
//
// The two actions are named "Dynamic Workspaces: Next Desktop" /
// "Dynamic Workspaces: Previous Desktop". Their default sequences are set
// here, but KGlobalAccel gives a stored value in kglobalshortcutsrc precedence
// over the sequence default, so the installer also writes the shortcuts
// explicitly through setForeignShortcut.

Item {
    id: root

    function isSpecial(d) {
        return d && d.name && d.name.startsWith("special:");
    }

    // KWin hands out different wrapper objects for the same desktop depending on
    // where they come from (Workspace.desktops, Workspace.currentDesktop, or a
    // window's desktops list), so identity comparisons silently fail - which is
    // exactly why "windows of this desktop" used to come out empty. Everything
    // below compares desktops by id instead.
    function desktopId(d) {
        return d ? (d.id ?? "") : "";
    }

    function indexOfDesktop(list, d) {
        const id = desktopId(d);
        if (id === "")
            return -1;
        for (let i = 0; i < list.length; i++) {
            if (desktopId(list[i]) === id)
                return i;
        }
        return -1;
    }

    /// The desktop the user is working on: the one holding the focused window.
    /// Workspace.currentDesktop does not always agree with what a window reports,
    /// so the focused window is the more trustworthy anchor.
    function anchorDesktop() {
        const w = activeWindow();
        if (w && w.desktops && w.desktops.length === 1)
            return w.desktops[0];
        return Workspace.currentDesktop;
    }

    // Normal desktops in workspace order.
    function normalDesktops() {
        return Workspace.desktops.filter(d => !isSpecial(d));
    }

    function desktopIsEmpty(d) {
        const wins = Workspace.stackingOrder.filter(w => w.normalWindow && !w.deleted && !w.onAllDesktops &&
                                                     indexOfDesktop(w.desktops ?? [], d) !== -1);
        return wins.length === 0;
    }

    function switchTo(d) {
        if (d)
            Workspace.currentDesktop = d;
    }

    /// The desktop after the current one. Past the last normal desktop a new one
    /// is created (and returned), so moving a window and switching to it behave
    /// identically.
    function nextTarget() {
        const normals = normalDesktops();
        if (normals.length === 0)
            return null;
        const idx = indexOfDesktop(normals, anchorDesktop());
        if (idx < 0) {
            // Currently on a special desktop: the first normal one.
            return normals[0];
        }
        if (idx + 1 < normals.length)
            return normals[idx + 1];

        const all = Workspace.desktops;
        const insertAt = all.indexOf(normals[normals.length - 1]) + 1;
        const before = new Set(all.map(d => d.id));
        Workspace.createDesktop(insertAt, "");
        const created = Workspace.desktops.find(d => !before.has(d.id));
        if (created)
            console.warn("dynamicworkspaces: created desktop at", insertAt);
        return created ?? null;
    }

    /// The desktop before the current one, or null when there is none.
    function previousTarget() {
        const normals = normalDesktops();
        if (normals.length === 0)
            return null;
        const idx = indexOfDesktop(normals, anchorDesktop());
        if (idx < 0)
            return normals[0];
        return idx > 0 ? normals[idx - 1] : null;
    }

    /// Windows that live on this one desktop. Windows shown on every desktop
    /// (empty desktops list) are deliberately left where they are.
    function windowsOn(d) {
        if (!d)
            return [];
        return Workspace.stackingOrder.filter(w => w.normalWindow && !w.deleted && !w.onAllDesktops &&
                                                  indexOfDesktop(w.desktops ?? [], d) !== -1);
    }

    /// The window that currently has keyboard focus. Workspace.activeWindow is
    /// not exposed by every KWin build (it is undefined here), so the stacking
    /// order is used as well.
    function activeWindow() {
        try {
            const w = Workspace.activeWindow;
            if (w && !w.deleted)
                return w;
        } catch (e) {
            // property missing in this KWin build
        }
        return Workspace.stackingOrder.find(x => x.active && x.normalWindow && !x.deleted) ?? null;
    }

    function moveWindowTo(win, d) {
        if (!win || !d || win.deleted)
            return false;
        win.desktops = [d];
        return true;
    }

    function nextDesktop() {
        const target = nextTarget();
        if (target)
            switchTo(target);
        recycleSoon();
    }

    function previousDesktop() {
        const target = previousTarget();
        if (target)
            switchTo(target);
    }

    /// Meta+Shift+PgDown / PgUp: take every window of this desktop along.
    function moveAll(direction: int) {
        const target = direction > 0 ? nextTarget() : previousTarget();
        if (!target)
            return;
        const from = anchorDesktop();
        const wins = windowsOn(from);
        for (const w of wins)
            w.desktops = [target];
        switchTo(target);
        recycleSoon();
        console.warn("dynamicworkspaces: moved", wins.length, "window(s) to", target.name);
    }

    /// Meta+Ctrl+PgDown / PgUp: take only the focused window along.
    function moveActive(direction: int) {
        const target = direction > 0 ? nextTarget() : previousTarget();
        if (!target)
            return;
        const win = activeWindow();
        if (moveWindowTo(win, target)) {
            switchTo(target);
            console.warn("dynamicworkspaces: moved", (win.resourceClass || "window"), "to", target.name);
        }
        recycleSoon();
    }

    // Remove empty normal desktops, keeping at most one. Never removes the
    // current desktop or special:* desktops.
    function recycle() {
        const normals = normalDesktops();
        if (normals.length <= 1)
            return;
        const empties = normals.filter(d => d !== Workspace.currentDesktop && desktopIsEmpty(d));
        while (empties.length > 1) {
            const victim = empties.pop();
            if (normals.length <= 1)
                break;
            console.warn("dynamicworkspaces: recycling empty desktop", victim.name);
            Workspace.removeDesktop(victim);
            normals.splice(normals.indexOf(victim), 1);
        }
    }

    function recycleSoon() {
        recycleDebounce.restart();
    }

    // Wires a Workspace signal to a callback. The signal lives on the global
    // Workspace singleton and therefore outlives this item, so a lambda that
    // used the root id directly would throw once root is destroyed (KWin
    // scripting can leave such connections behind when a script is unloaded).
    // The null guard keeps a stale connection silent instead of spamming the
    // journal.
    function tryConnect(obj, sig, fn) {
        try {
            if (obj[sig] !== undefined)
                obj[sig].connect(() => {
                    if (root)
                        fn();
                });
        } catch (e) {
            console.warn("dynamicworkspaces: cannot connect", sig, e);
        }
    }

    Timer {
        id: recycleDebounce

        interval: 400
        onTriggered: {
            if (root)
                root.recycle();
        }
    }

    ShortcutHandler {
        name: "Dynamic Workspaces: Next Desktop"
        text: "Switch to the next desktop, creating one past the last"
        sequence: "Meta+PgDown"
        onActivated: root.nextDesktop()
    }

    ShortcutHandler {
        name: "Dynamic Workspaces: Previous Desktop"
        text: "Switch to the previous desktop"
        sequence: "Meta+PgUp"
        onActivated: root.previousDesktop()
    }

    ShortcutHandler {
        name: "Dynamic Workspaces: Move All Windows to Next Desktop"
        text: "Move every window of this desktop to the next desktop"
        sequence: "Meta+Shift+PgDown"
        onActivated: root.moveAll(1)
    }

    ShortcutHandler {
        name: "Dynamic Workspaces: Move All Windows to Previous Desktop"
        text: "Move every window of this desktop to the previous desktop"
        sequence: "Meta+Shift+PgUp"
        onActivated: root.moveAll(-1)
    }

    ShortcutHandler {
        name: "Dynamic Workspaces: Move Window to Next Desktop"
        text: "Move the focused window to the next desktop"
        sequence: "Meta+Ctrl+PgDown"
        onActivated: root.moveActive(1)
    }

    ShortcutHandler {
        name: "Dynamic Workspaces: Move Window to Previous Desktop"
        text: "Move the focused window to the previous desktop"
        sequence: "Meta+Ctrl+PgUp"
        onActivated: root.moveActive(-1)
    }

    Component.onCompleted: {
        console.warn("dynamicworkspaces: script started, desktops =", Workspace.desktops.length);
        recycleSoon();
        tryConnect(Workspace, "windowRemoved", () => recycleSoon());
        tryConnect(Workspace, "clientRemoved", () => recycleSoon());
        tryConnect(Workspace, "currentDesktopChanged", () => recycleSoon());
        tryConnect(Workspace, "desktopsChanged", () => recycleSoon());
        tryConnect(Workspace, "countChanged", () => recycleSoon());
    }
}
