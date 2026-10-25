#!/usr/bin/env bash
# PlasmaZones: KWin snap zones / autotile / scrolling layouts, driven by the
# plasmazonesd user service and a KWin effect. This is the tiling backend the
# Caelestia desktop uses instead of a KWin script.

PLASMAZONES_COPR="${PLASMAZONES_COPR:-fuddlesworth/PlasmaZones}"

plasmazones_present() {
    command -v plasmazonesd >/dev/null 2>&1
}

plasmazones_install_packages() {
    if plasmazones_present; then
        ok "PlasmaZones is already installed."
        return 0
    fi

    case "${BASE_DISTRO:-fedora}" in
    fedora)
        if ! command -v dnf >/dev/null 2>&1; then
            warn "dnf not found - skipping PlasmaZones."
            return 1
        fi
        # PlasmaZones ships in the Fedora repositories on recent releases and in
        # the maintainer's COPR otherwise, so try the plain install first.
        if caelestia_sudo dnf install -y plasmazones >/dev/null 2>&1; then
            ok "PlasmaZones installed from the Fedora repositories."
        elif caelestia_sudo dnf copr enable -y "$PLASMAZONES_COPR" >/dev/null 2>&1 &&
            caelestia_sudo dnf install -y plasmazones >/dev/null 2>&1; then
            ok "PlasmaZones installed from COPR $PLASMAZONES_COPR."
        else
            warn "Could not install PlasmaZones - skipping."
            return 1
        fi
        ;;
    arch)
        if command -v yay >/dev/null 2>&1; then
            yay -S --needed --noconfirm plasmazones-bin || {
                warn "Could not install plasmazones-bin - skipping."
                return 1
            }
        else
            warn "yay not found - install plasmazones-bin manually."
            return 1
        fi
        ;;
    *)
        warn "No PlasmaZones package source for $BASE_DISTRO - skipping."
        return 1
        ;;
    esac

    plasmazones_present || return 1
}

plasmazones_drop_legacy_window_positions() {
    # Older setups used the third-party "Remember Window Positions" KWin script.
    # PlasmaZones owns window placement now, and both fighting over geometry
    # makes zones feel broken, so the script is unloaded and removed.
    kwriteconfig6 --file kwinrc --group Plugins --key rememberwindowpositionsEnabled false 2>/dev/null || true

    local script_dir="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/rememberwindowpositions"
    if [[ -d "$script_dir" ]] && command -v qdbus6 >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript rememberwindowpositions >/dev/null 2>&1 || true
    fi
    if [[ -d "$script_dir" ]]; then
        rm -rf "$script_dir"
        ok "Removed the Remember Window Positions KWin script."
    fi

    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    fi
}

plasmazones_enable() {
    # The daemon owns layouts and shortcuts; the KWin effect paints the overlay.
    # A missing systemd user session (e.g. run from a TTY) is not fatal.
    if command -v systemctl >/dev/null 2>&1 && [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        systemctl --user enable --now plasmazones.service >/dev/null 2>&1 ||
            warn "Could not start plasmazones.service - start it after the next login."
    fi

    # KWin only spells effect keys without the "kwin_effect_" prefix.
    kwriteconfig6 --file kwinrc --group Plugins --key plasmazonesEnabled true 2>/dev/null || true

    if command -v qdbus6 >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
    fi

    ok "PlasmaZones enabled (the effect loads on the next KWin start)."
}

plasmazones_setup() {
    if [[ "${INSTALL_PLASMAZONES:-true}" != "true" ]]; then
        info "INSTALL_PLASMAZONES is off - skipping PlasmaZones."
        return 0
    fi

    info "Setting up PlasmaZones..."
    plasmazones_drop_legacy_window_positions
    plasmazones_install_packages || return 0
    plasmazones_enable
}

