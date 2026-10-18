pragma Singleton

import Quickshell
import Caelestia.Config
import qs.utils

Singleton {
    id: root

    /// Exec command with the field codes stripped and whitespace collapsed.
    /// Two desktop files that run exactly the same thing describe the same
    /// application, however differently they are named.
    function execKey(entry: DesktopEntry): string {
        return (entry?.execString ?? "").replace(/%[fFuUdDnNickvm]/g, "").replace(/\s+/g, " ").trim();
    }

    /// An id the user has already committed to (dock pin or favourite) must
    /// never be dropped in favour of a duplicate's id, or the pin would stop
    /// matching the launcher entry.
    function isPreferred(id: string): bool {
        return Strings.testRegexList(GlobalConfig.bar.dock.pinnedApps, id) //
            || Strings.testRegexList(GlobalConfig.launcher.favouriteApps, id);
    }

    /// Collapse entries that share an Exec command into a single one.
    ///
    /// A package that installs its desktop files both directly into an XDG
    /// data dir and into a subdirectory of another one makes the same
    /// application show up twice, because the desktop file id is derived from
    /// the path (`wechat` vs `apm-wechat`). This is what the Spark Store's
    /// ACE/amber packages do, so WeChat, QQ and DingTalk were listed twice.
    ///
    /// Winner: a pinned/favourite id if there is one, otherwise the shortest
    /// id - the one without the redundant directory prefix.
    function dedupe(entries: var): var {
        const byExec = new Map();
        const keyOrder = [];

        for (const entry of entries) {
            const key = execKey(entry);
            const current = byExec.get(key);

            if (current === undefined) {
                byExec.set(key, entry);
                keyOrder.push(key);
                continue;
            }

            const currentPreferred = isPreferred(current.id);
            const entryPreferred = isPreferred(entry.id);

            if (entryPreferred !== currentPreferred) {
                if (entryPreferred)
                    byExec.set(key, entry);
            } else if (entry.id.length < current.id.length //
                || (entry.id.length === current.id.length && entry.id < current.id)) {
                byExec.set(key, entry);
            }
        }

        return keyOrder.map(key => byExec.get(key));
    }

    /// What an app list should show: everything the user has not hidden, with
    /// duplicates collapsed.
    function visible(entries: var): var {
        return root.dedupe(entries.filter(e => !Strings.testRegexList(GlobalConfig.launcher.hiddenApps, e.id)));
    }

    /// Every installed application, deduplicated, sorted by name.
    function allSorted(): var {
        return root.visible(DesktopEntries.applications.values).sort((a, b) => a.name.localeCompare(b.name));
    }
}
