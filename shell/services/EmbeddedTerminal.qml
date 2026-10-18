pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import qs.services

/// Runs commands in the shell's own terminal, i.e. the dashboard's "Terminal"
/// tab (modules/dashboard/TerminalTab.qml).
///
/// The tab is built lazily, so a request can arrive before it exists (or while
/// the dashboard is closed): requests are queued here and the tab drains the
/// queue when it appears. Commands are passed as an argv array rather than as a
/// command line, so nothing has to be quoted and re-parsed by a shell.
Singleton {
    id: root

    /// Pending { argv: list<string>, directory: string, screen: string } jobs.
    property var queue: []

    /// Emitted when a job is added; the terminal tab listens for this.
    signal requested

    /// Index of the terminal tab on a screen. The tab list in
    /// modules/dashboard/Content.qml ends with the terminal, so it is the last
    /// enabled tab.
    function terminalTabIndex(screenName: string): int {
        const cfg = GlobalConfig.forScreen(screenName).dashboard;
        let idx = 0;
        if (cfg.showDashboard)
            idx++;
        if (cfg.showMedia)
            idx++;
        if (cfg.showPerformance)
            idx++;
        if (cfg.showWeather)
            idx++;
        return idx;
    }

    /// Whether the shell's terminal tab exists at all.
    function available(screenName: string): bool {
        return GlobalConfig.forScreen(screenName).dashboard.showTerminal;
    }

    /// Open the dashboard on its terminal tab.
    function reveal(screenName: string): void {
        const screens = Screens.screens ?? [];
        const screen = screens.find(s => s.name === screenName) ?? screens[0];
        if (!screen)
            return;

        const vis = Visibilities.screens.get(Kwin.monitorFor(screen));
        if (vis) {
            vis.launcher = false;
            vis.dashboard = true;
        }
        ShellState.forScreen(screen).dashboardTab = root.terminalTabIndex(screen.name);
    }

    /// Queue a command (argv) and bring the terminal tab to the front.
    function run(argv: var, directory: string, screenName: string): void {
        if (!argv || argv.length === 0)
            return;
        root.queue = [...root.queue, { argv: argv, directory: directory ?? "", screen: screenName ?? "" }];
        root.reveal(screenName);
        root.requested();
    }

    /// Next job for this screen, or null when there is nothing left for it. Jobs
    /// queued without a screen (unknown caller screen) go to whichever terminal
    /// asks first.
    function take(screenName: string): var {
        const idx = root.queue.findIndex(j => j.screen === "" || j.screen === screenName);
        if (idx === -1)
            return null;
        const job = root.queue[idx];
        root.queue = root.queue.filter((_, i) => i !== idx);
        return job;
    }
}
