#!/usr/bin/env bash

# Airlock login screen: a Material 3 greetd greeter built on Quickshell.
#
# Airlock (https://github.com/AstraSuite/Airlock) is a greetd frontend built on
# Quickshell, deliberately styled to match the Caelestia shell: it reuses
# Caelestia's M3Shapes module, clock design and Google Sans Flex font, so the
# login screen looks like the session behind it. This is the default login
# screen for new installs; SDDM remains available as an alternative.
#
# The greeter runs as the unprivileged "greeter" user on its own cage
# compositor, which is why the palette, avatar and wallpaper have to be copied
# into /var/cache/astra-airlock: that account cannot read /home/<user>.

# shellcheck source=log.sh
source "$(dirname "${BASH_SOURCE[0]}")/log.sh"
# shellcheck source=privileges.sh
source "$(dirname "${BASH_SOURCE[0]}")/privileges.sh"
# shellcheck source=packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/packages.sh"

AIRLOCK_REPO="${AIRLOCK_REPO:-https://github.com/AstraSuite/Airlock.git}"
AIRLOCK_SRC="${AIRLOCK_SRC:-${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde/astra-airlock}"
AIRLOCK_CACHE="/var/cache/astra-airlock"
GREETER_USER="greeter"
SYSTEM_QML_DIR="/usr/lib64/qt6/qml"

greeter_airlock_deps() {
    # Package names differ per distro; the first candidate that resolves wins.
    install_if_missing greetd greetd || true
    install_if_missing cage cage || true
    install_if_missing wlr-randr wlr-randr || true

    case "${BASE_DISTRO:-unknown}" in
        arch)
            install_if_missing cmake cmake || true
            install_if_missing ninja ninja || true
            install_if_missing qt6-base qt6-base || true
            install_if_missing qt6-declarative qt6-declarative || true
            ;;
        fedora)
            install_if_missing cmake cmake || true
            install_if_missing ninja-build ninja-build || true
            install_if_missing qt6-qtbase-devel qt6-qtbase-devel || true
            install_if_missing qt6-qtdeclarative-devel qt6-qtdeclarative-devel || true
            ;;
        debian)
            install_if_missing cmake cmake || true
            install_if_missing ninja-build ninja-build || true
            install_if_missing qt6-base-dev qt6-base-dev || true
            install_if_missing qt6-declarative-dev qt6-declarative-dev || true
            ;;
    esac

    local missing=()
    for bin in greetd cage astra-airlock cmake ninja python3; do
        command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
    done
    # astra-airlock is built below, so only complain about what a package manager
    # was supposed to provide.
    local blockers=()
    for bin in "${missing[@]}"; do
        [[ "$bin" == "astra-airlock" ]] && continue
        blockers+=("$bin")
    done
    if (( ${#blockers[@]} > 0 )); then
        warn "greetd/Airlock prerequisites still missing: ${blockers[*]}"
        return 1
    fi
    return 0
}

build_airlock() {
    install -d "$AIRLOCK_SRC"
    if [[ -d "$AIRLOCK_SRC/.git" ]]; then
        git -C "$AIRLOCK_SRC" fetch --depth 1 origin main >/dev/null 2>&1 || true
        git -C "$AIRLOCK_SRC" reset --hard origin/main >/dev/null 2>&1 || true
    else
        rm -rf "$AIRLOCK_SRC"
        git clone --depth 1 "$AIRLOCK_REPO" "$AIRLOCK_SRC" >/dev/null 2>&1 || {
            warn "could not clone $AIRLOCK_REPO"
            return 1
        }
    fi

    cmake -S "$AIRLOCK_SRC" -B "$AIRLOCK_SRC/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release >/dev/null 2>&1 || {
        warn "cmake configure failed for Airlock"
        return 1
    }
    cmake --build "$AIRLOCK_SRC/build" >/dev/null 2>&1 || {
        warn "cmake build failed for Airlock"
        return 1
    }
    return 0
}

# The greeter account cannot read ~/.local, so every QML module Airlock imports
# has to exist system-wide. M3Shapes and the Caelestia modules come from the
# shell this repo already builds.
install_airlock_runtime() {
    caelestia_sudo cmake --install "$AIRLOCK_SRC/build" >/dev/null 2>&1 || {
        warn "could not install Airlock"
        return 1
    }

    local qml_root="${CAELESTIA_QML_DIR:-$HOME/.local/lib/qt6/qml}"
    caelestia_sudo install -d "$SYSTEM_QML_DIR"

    if [[ -d "$qml_root/M3Shapes" ]]; then
        caelestia_sudo rm -rf "$SYSTEM_QML_DIR/M3Shapes"
        caelestia_sudo cp -a "$qml_root/M3Shapes" "$SYSTEM_QML_DIR/"
    else
        warn "M3Shapes is missing from $qml_root; build the shell first"
        return 1
    fi

    if [[ -d "$qml_root/Caelestia" ]]; then
        caelestia_sudo rm -rf "$SYSTEM_QML_DIR/Caelestia"
        caelestia_sudo cp -a "$qml_root/Caelestia" "$SYSTEM_QML_DIR/"
    fi

    caelestia_sudo chmod -R a+rX "$SYSTEM_QML_DIR/M3Shapes"
    [[ -d "$SYSTEM_QML_DIR/Caelestia" ]] && caelestia_sudo chmod -R a+rX "$SYSTEM_QML_DIR/Caelestia"
    return 0
}

# Airlock draws every icon in the interface (power, session arrows, battery,
# the caps-lock hint, the password reveal toggle) with the Material Symbols
# Rounded font, and unlike Google Sans Flex and Titan One it neither bundles nor
# FontLoaders it. The installer downloads that font into the user's own font
# directory, which the greeter account cannot read, so the login screen would
# render tofu boxes where the desktop renders glyphs. Install the same file
# system-wide, then check it resolves for the greeter exactly as its Qt would.
GREETER_FONT_DIR="/usr/share/fonts/google-material-symbols"
MATERIAL_SYMBOLS_URL="https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf"

install_greeter_fonts() {
    local user_font="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/MaterialSymbolsRounded.ttf"
    local target="$GREETER_FONT_DIR/MaterialSymbolsRounded.ttf"
    local tmp

    caelestia_sudo install -d -m 0755 "$GREETER_FONT_DIR"

    if [[ ! -f "$target" ]]; then
        if [[ -f "$user_font" ]]; then
            caelestia_sudo install -m 0644 "$user_font" "$target"
        elif command -v curl >/dev/null 2>&1; then
            tmp="$(mktemp)"
            if curl -fsSL "$MATERIAL_SYMBOLS_URL" -o "$tmp" && [[ -s "$tmp" ]]; then
                caelestia_sudo install -m 0644 "$tmp" "$target"
            else
                warn "could not fetch the Material Symbols font; the login screen will show missing glyphs"
                rm -f "$tmp"
                return 1
            fi
            rm -f "$tmp"
        else
            warn "no Material Symbols font available; the login screen will show missing glyphs"
            return 1
        fi
    fi

    caelestia_sudo chmod 0644 "$target"
    caelestia_sudo fc-cache -f >/dev/null 2>&1 || true

    # fontconfig caches are per user, and the greeter has its own home, so the
    # root-side cache refresh above proves nothing about what the greeter sees.
    if command -v runuser >/dev/null 2>&1 && getent passwd "$GREETER_USER" >/dev/null 2>&1; then
        if ! HOME="$AIRLOCK_CACHE" runuser -u "$GREETER_USER" -- fc-match "Material Symbols Rounded" 2>/dev/null \
            | grep -q MaterialSymbolsRounded; then
            warn "the greeter cannot resolve Material Symbols Rounded; its icons will be blank"
            return 1
        fi
    fi
    return 0
}

ensure_greeter_user() {
    if ! getent passwd "$GREETER_USER" >/dev/null 2>&1; then
        caelestia_sudo useradd -r -M -s /usr/sbin/nologin -d "$AIRLOCK_CACHE" "$GREETER_USER" \
            2>/dev/null || caelestia_sudo useradd -r -M -s /sbin/nologin -d "$AIRLOCK_CACHE" "$GREETER_USER"
    fi
    caelestia_sudo usermod -aG video,input,render "$GREETER_USER" >/dev/null 2>&1 || true
    caelestia_sudo install -d -m 0755 -o "$GREETER_USER" -g "$GREETER_USER" "$AIRLOCK_CACHE"
}

write_greetd_config() {
    caelestia_sudo install -d -m 0755 /etc/greetd
    if [[ -f /etc/greetd/config.toml ]] && [[ ! -f /etc/greetd/config.toml.caelestia-orig ]]; then
        caelestia_sudo cp -a /etc/greetd/config.toml /etc/greetd/config.toml.caelestia-orig
    fi

    # Cage is the smallest compositor that can host a Quickshell surface; the
    # redirect keeps the tty from flashing compositor logs before the greeter.
    caelestia_sudo tee /etc/greetd/config.toml >/dev/null << TOML
[terminal]
vt = 1

[default_session]
command = "cage -s -- astra-airlock >/dev/null 2>&1"
user = "$GREETER_USER"
TOML
}

# The greeter reads its palette from /var/cache/astra-airlock, not from the
# user's home, so mirror the live scheme/avatar/wallpaper in there.
sync_greeter_state() {
    local scheme="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/scheme.json"
    local wall_file="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/wallpaper/path.txt"
    local user="${USER:-$(id -un)}"

    # The helper mirrors the palette, avatar and wallpaper in one place, and is
    # the same script the palette post-hook calls on every theme change.
    local helper="$(dirname "${BASH_SOURCE[0]}")/caelestia-airlock-sync"
    if [[ -f "$helper" ]]; then
        caelestia_sudo install -m 0755 "$helper" /usr/local/bin/caelestia-airlock-sync
        caelestia_sudo SUDO_USER="$user" /usr/local/bin/caelestia-airlock-sync >/dev/null 2>&1 || true
    fi

    # Avatars and wallpaper go through the launcher so it places them where
    # the greeter looks and fixes their ownership.
    if [[ -f "$HOME/.face" ]]; then
        caelestia_sudo SUDO_USER="$user" astra-airlock --set-pfp "$HOME/.face" >/dev/null 2>&1 || true
    fi
    if [[ -f "$wall_file" ]]; then
        local wall
        wall="$(cat "$wall_file" 2>/dev/null || true)"
        if [[ -n "$wall" && -f "$wall" ]]; then
            caelestia_sudo SUDO_USER="$user" astra-airlock --set-wallpaper "$wall" >/dev/null 2>&1 || true
        fi
    fi

    caelestia_sudo chown -R "$GREETER_USER:$GREETER_USER" "$AIRLOCK_CACHE" 2>/dev/null || true
    caelestia_sudo chmod -R a+rX "$AIRLOCK_CACHE"
}

# Caelestia ships its scheme collection inside the shell package, which the
# greeter cannot read either.
install_scheme_collection() {
    local schemes="${CAELESTIA_LIB_DIR:-$HOME/.local/lib/caelestia}/schemes"
    [[ -d "$schemes" ]] || return 0
    caelestia_sudo install -d /usr/share/caelestia
    caelestia_sudo rm -rf /usr/share/caelestia/schemes
    caelestia_sudo cp -a "$schemes" /usr/share/caelestia/
    caelestia_sudo chmod -R a+rX /usr/share/caelestia/schemes
}

# Re-sync the greeter whenever the desktop palette changes, exactly like the
# SDDM path does.
#
# Airlock's own `--sync` flag shells out to the upstream Python caelestia-cli,
# which this repo does not install (it ships a bash CLI). So the hook runs our
# own helper instead, reading the same scheme file the desktop reads.
register_airlock_sync() {
    local cli_json="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/cli.json"
    local helper=/usr/local/bin/caelestia-airlock-sync
    local source_helper="$(dirname "${BASH_SOURCE[0]}")/caelestia-airlock-sync"
    local hook="sudo -n $helper"
    local sudoers=/etc/sudoers.d/caelestia-airlock-sync

    if [[ -f "$source_helper" ]]; then
        caelestia_sudo install -d -m 0755 /usr/local/bin
        caelestia_sudo install -m 0755 "$source_helper" "$helper"
    fi

    command -v python3 >/dev/null 2>&1 || {
        warn "python3 is required to register the greeter sync hook"
        return 0
    }

    install -d "$(dirname "$cli_json")"
    [[ -f "$cli_json" ]] || echo '{}' > "$cli_json"
    python3 - "$cli_json" "$hook" << 'PY'
import json, sys
path, hook = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception:
    data = {}
for section in ("theme", "wallpaper"):
    block = data.setdefault(section, {})
    current = block.get("postHook", "")
    # Airlock's own --sync cannot work without the Python CLI; replace it.
    current = current.replace("sudo -n astra-airlock --sync", hook)
    if hook in current:
        block["postHook"] = current
        continue
    block["postHook"] = (current + " && " + hook) if current else hook
with open(path, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
PY

    # The sync needs root; allow exactly the helper without a password.
    printf '%s ALL=(ALL) NOPASSWD: /usr/bin/astra-airlock -s, /usr/bin/astra-airlock --sync, %s\n' \
        "${USER:-$(id -un)}" "$helper" > /tmp/caelestia-airlock-sudoers
    if caelestia_sudo visudo -cf /tmp/caelestia-airlock-sudoers >/dev/null 2>&1; then
        caelestia_sudo install -m 0440 -o root -g root /tmp/caelestia-airlock-sudoers "$sudoers"
    fi
    rm -f /tmp/caelestia-airlock-sudoers
}

enable_greetd() {
    # The KDE lock screen is a separate mechanism (kscreenlocker), so switching
    # the display manager does not touch it.
    caelestia_sudo systemctl disable sddm.service >/dev/null 2>&1 || true
    caelestia_sudo systemctl enable greetd.service >/dev/null 2>&1 || true
}

greetd_airlock_install() {
    if ! greeter_airlock_deps; then
        warn "Skipping the Airlock login screen: prerequisites are missing."
        return 1
    fi

    info "Building Airlock from $AIRLOCK_REPO"
    build_airlock || return 1

    info "Installing the greeter and the QML modules it imports"
    install_airlock_runtime || return 1
    install_scheme_collection

    ensure_greeter_user
    install_greeter_fonts || warn "the login screen icons may not render"
    write_greetd_config
    sync_greeter_state
    register_airlock_sync
    enable_greetd

    ok "Airlock installed as the greetd login screen."
    return 0
}
