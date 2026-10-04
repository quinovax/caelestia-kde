pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin

// Dynamic virtual desktops for KWin (Plasma 6).
//
// - Meta+PgDown: switch to the next *normal* desktop (skips caelestia's
//   "special:*" desktops); past the last one, a new desktop is created and
//   switched to.
// - Meta+PgUp: switch to the previous normal desktop (clamped at the first).
// - Recycling: normal desktops with no windows are removed, keeping at most
//   one empty desktop. special:* desktops are never touched.

Item {
    id: root

    function isSpecial(d) {
        return d && d.name && d.name.startsWith("special:");
    }

    // Normal desktops in workspace order.
    function normalDesktops() {
        return Workspace.desktops.filter(d => !isSpecial(d));
    }

    function desktopIsEmpty(d) {
        // A window counts towards a desktop if it is a normal window placed on
        // it (window.desktops covers all-desktops windows as well).
        const wins = Workspace.stackingOrder.filter(w => w.normalWindow && !w.deleted &&
                                                     w.desktops.includes(d));
        return wins.length === 0;
    }

    function switchTo(d) {
        if (d)
            Workspace.currentDesktop = d;
    }

    function nextDesktop() {
        const normals = normalDesktops();
        const idx = normals.indexOf(Workspace.currentDesktop);
        if (idx < 0) {
            // Currently on a special desktop: go to the first normal one.
            switchTo(normals[0]);
            return;
        }
        if (idx + 1 < normals.length) {
            switchTo(normals[idx + 1]);
            return;
        }
        // Past the last normal desktop: create a new one right after it and
        // switch to it.
        const all = Workspace.desktops;
        const insertAt = all.indexOf(normals[normals.length - 1]) + 1;
        const before = new Set(all.map(d => d.id));
        Workspace.createDesktop(insertAt, "");
        const created = Workspace.desktops.find(d => !before.has(d.id));
        if (created) {
            console.warn("dynamicworkspaces: created desktop at", insertAt, "and switching");
            switchTo(created);
        }
        recycleSoon();
    }

    function previousDesktop() {
        const normals = normalDesktops();
        const idx = normals.indexOf(Workspace.currentDesktop);
        if (idx < 0) {
            switchTo(normals[0]);
            return;
        }
        if (idx > 0)
            switchTo(normals[idx - 1]);
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

    function tryConnect(obj, sig, fn) {
        try {
            if (obj[sig] !== undefined)
                obj[sig].connect(fn);
        } catch (e) {
            console.warn("dynamicworkspaces: cannot connect", sig, e);
        }
    }

    Timer {
        id: recycleDebounce

        interval: 400
        onTriggered: root.recycle()
    }

    ShortcutHandler {
        name: "DWS Next"
        text: "Switch to the next desktop, creating one past the last"
        sequence: "Meta+PgDown"
        onActivated: root.nextDesktop()
    }

    ShortcutHandler {
        name: "DWS Previous"
        text: "Switch to the previous desktop"
        sequence: "Meta+PgUp"
        onActivated: root.previousDesktop()
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
