#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"

echo
echo ""
echo "  Caelestia  Live System Tweaks"
echo ""

tweak_disable_kde_osd() {
    info "Disabling KDE OSD popups (volume/brightness)..."

    kwriteconfig6 --file plasmarc --group "OSD" --key "Enabled" "false" 2>/dev/null || true
    kwriteconfig6 --file plasmarc --group "OSD" --key "ShowOnActiveScreen" "false" 2>/dev/null || true

    kwriteconfig6 --file kdeglobals --group "KDE" --key "OSDEnabled" "false" 2>/dev/null || true

    kwriteconfig6 --file plasmanotifyrc --group "Notifications" \
        --key "LoudnessChangedOSD" "false" 2>/dev/null || true

    kwriteconfig6 --file powerdevilrc --group "BrightnessControl" \
        --key "showOSD" "false" 2>/dev/null || true
    kwriteconfig6 --file powerdevilrc --group "AC" \
        --key "brightnessosd" "false" 2>/dev/null || true

    kwriteconfig6 --file kmixrc --group "Global" --key "ShowOSD" "false" 2>/dev/null || true

    ok "KDE OSD popups disabled."
}

first_install() {
    local existing
    existing="$(kreadconfig6 --file kwinrc --group "Desktops" --key "Number" 2>/dev/null || true)"
    [[ -z "$existing" ]]
}

tweak_five_desktops() {
    if ! first_install; then
        skip "Existing virtual desktop configuration found - leaving it untouched."
        return 0
    fi
    info "Configuring 5 virtual desktops..."

    kwriteconfig6 --file kwinrc --group "Desktops" --key "Number" "5"
    kwriteconfig6 --file kwinrc --group "Desktops" --key "Rows" "1"
    for i in $(seq 1 5); do
        kwriteconfig6 --file kwinrc --group "Desktops" --key "Name_$i" "Desktop $i"
    done

    ok "5 virtual desktops configured."
}

tweak_remove_panels() {
    if ! first_install; then
        skip "Not a first install - leaving Plasma panels alone."
        return 0
    fi
    info "Removing KDE Plasma panels..."

    if qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "var p = panels(); for (var i = 0; i < p.length; i++) { p[i].remove(); }" \
        2>/dev/null; then
        ok "KDE panels removed."
        return 0
    fi

    python3 - <<'EOF' || warn "Failed to remove KDE panels from config."
import os
import re

path = os.path.expanduser("~/.config/plasma-org.kde.plasma.desktop-appletsrc")
if not os.path.exists(path):
    raise SystemExit(0)

lines = open(path, "r", encoding="utf-8").read().splitlines()

panel_ids = set()
current = None
for line in lines:
    s = line.strip()
    m = re.match(r"^\[Containments\]\[(\d+)\]$", s)
    if m:
        current = m.group(1)
    elif s.startswith("[Containments][") and not re.match(r"^\[Containments\]\[\d+\]$", s):
        continue
    elif s.startswith("[") and s.endswith("]"):
        current = None
    elif current is not None and re.match(r"^(formfactor\s*=\s*[23]|plugin\s*=\s*org\.kde\.plasma\.panel)\s*$", s, re.IGNORECASE):
        panel_ids.add(current)

if not panel_ids:
    raise SystemExit(0)

out = []
skip = False
for line in lines:
    s = line.strip()
    m = re.match(r"^\[Containments\]\[(\d+)\]$", s)
    if m:
        skip = m.group(1) in panel_ids
        if skip:
            continue
    elif s.startswith("[Containments][") and not m:
        pass
    elif s.startswith("[") and s.endswith("]"):
        skip = False
    if skip:
        continue
    out.append(line)

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print(f"Removed {len(panel_ids)} KDE panel(s)")
EOF

    ok "KDE panels removed."
}

tweak_no_splash_screen() {
    info "Turning off the Plasma startup splash..."

    kwriteconfig6 --file ksplashrc --group KSplash --key Engine "none" 2>/dev/null || true

    ok "Plasma splash screen disabled."
}

tweak_reload_kde() {
    info "Reloading KWin and plasma-kglobalaccel..."
    qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
    systemctl --user restart plasma-kglobalaccel.service 2>/dev/null || true
    ok "KDE daemons reloaded."
}

tweak_default_scheme() {
    info "Setting default Caelestia color scheme..."
    if command -v caelestia >/dev/null 2>&1; then
        STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia"
        CURRENT=""
        if [[ -s "$STATE_DIR/scheme.json" ]] && command -v python3 >/dev/null 2>&1; then
            CURRENT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name", ""))' "$STATE_DIR/scheme.json" 2>/dev/null || true)"
        fi
        if [[ -n "$CURRENT" && "$CURRENT" != "dynamic" ]]; then
            info "Keeping user-selected Caelestia color scheme ($CURRENT)."
            ok "Default Caelestia color scheme kept."
            return
        fi

        WALLPAPER="$(cat "$STATE_DIR/wallpaper/path.txt" 2>/dev/null || true)"
        if [[ -n "$WALLPAPER" && -f "$WALLPAPER" ]]; then
            timeout 10s caelestia wallpaper -f "$WALLPAPER" >/dev/null 2>&1 || true
        fi
        timeout 10s caelestia scheme set -n dynamic >/dev/null 2>&1 || true
    fi
    ok "Default Caelestia color scheme set."
}


tweak_default_shell() {
    local target_shell="${DEFAULT_SHELL:-fish}"
    info "Setting default shell to $target_shell..."

    if command -v "$target_shell" >/dev/null 2>&1; then
        local shell_path
        shell_path="$(command -v "$target_shell")"

        local current_shell
        current_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"
        if [[ -z "$current_shell" ]]; then
            current_shell="$SHELL"
        fi

        if [[ "$current_shell" == "$shell_path" ]]; then
            info "Shell is already set to $shell_path. Skipping chsh."
        else
            caelestia_sudo_quiet chsh -s "$shell_path" "$(id -un)" 2>/dev/null || warn "Failed to change shell without prompting. You may need to run 'sudo chsh -s $shell_path $(id -un)' manually."
        fi

        local konsole_profile_dir="$HOME/.local/share/konsole"
        mkdir -p "$konsole_profile_dir"

        local profiles_found=0
        for profile in "$konsole_profile_dir"/*.profile; do
            if [[ -f "$profile" ]]; then
                kwriteconfig6 --file "$profile" --group "General" --key "Command" "$shell_path"
                profiles_found=1
            fi
        done

        if [[ $profiles_found -eq 0 ]]; then
            kwriteconfig6 --file "$konsole_profile_dir/Profile 1.profile" --group "General" --key "Name" "Profile 1"
            kwriteconfig6 --file "$konsole_profile_dir/Profile 1.profile" --group "General" --key "Command" "$shell_path"
            kwriteconfig6 --file "$HOME/.config/konsolerc" --group "Desktop Entry" --key "DefaultProfile" "Profile 1.profile"
        fi
    else
        warn "$target_shell is not installed, skipping shell change."
    fi

    ok "Shell configuration applied."
}

tweak_user_avatar_symlinks() {
    if [[ -e "$HOME/.face.icon" || -L "$HOME/.face.icon" ]]; then
        # shellcheck disable=SC2088
        info "~/.face.icon already exists. Skipping avatar setup."
        return 0
    fi

    info "Setting up user profile picture symlinks..."

    local user_name="${USER:-$(id -un)}"
    local account_icon="/var/lib/AccountsService/icons/$user_name"

    if [[ -f "$account_icon" ]]; then
        ln -sf "$account_icon" "$HOME/.face"
        ln -sf "$account_icon" "$HOME/.face.icon"
        info "Linked $account_icon -> $HOME/.face"
        info "Linked $account_icon -> $HOME/.face.icon"
        ok "User profile picture symlinks configured."
    else
        info "No AccountsService avatar found at $account_icon. Skipping."
    fi
}


# ---------------------------------------------------------------- Quinovax ---
# The KDE port ships its own desktop defaults on top of upstream: a dynamic
# virtual desktops KWin script, the genie (Magic Lamp) minimize animation, a
# rule that hides xwaylandvideobridge's black blob, and the global shortcut
# set. They live here rather than in their own step so no TUI rebuild is
# needed - Runner.cpp's step table is compiled into the installer binary.

tweak_kwin_scripts_and_effects() {
    local bundle="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local scripts_root="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts"
    local script

    for script in dynamicworkspaces genieshowdesktop; do
        local src="$bundle/kwin-scripts/$script"
        local dst="$scripts_root/$script"

        info "Installing KWin script: $script..."
        if [[ -d "$src" ]]; then
            mkdir -p "$scripts_root"
            rm -rf "$dst" 2>/dev/null || true
            cp -a "$src" "$dst"
            ok "Installed KWin script: $script"
        else
            warn "Missing $src - $script will not be available."
        fi
    done

    info "Enabling KWin effects and window rules..."
    # Magic Lamp is the only effect in KWin's "minimize" exclusive group, so
    # enabling it (and keeping Squash off) makes the genie animation the
    # default minimize/restore animation.
    kwriteconfig6 --file kwinrc --group Plugins --key dynamicworkspacesEnabled true 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group Plugins --key genieshowdesktopEnabled true 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group Plugins --key magiclampEnabled true 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group Plugins --key squashEnabled false 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group Plugins --key rememberwindowpositionsEnabled true 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group Effect-magiclamp --key AnimationDuration 300 2>/dev/null || true

    # xwaylandvideobridge shows up as a black blob on the desktop; the only
    # thing a user can do with it is look at it, so hide it everywhere.
    local group="xwaylandbridge-hide"
    kwriteconfig6 --file kwinrulesrc --group "$group" --key Description "Hide xwaylandvideobridge (black blob fix)"
    kwriteconfig6 --file kwinrulesrc --group "$group" --key enabled true
    kwriteconfig6 --file kwinrulesrc --group "$group" --key types 1
    kwriteconfig6 --file kwinrulesrc --group "$group" --key wmclassmatch 3
    kwriteconfig6 --file kwinrulesrc --group "$group" --key wmclasscomplete false
    kwriteconfig6 --file kwinrulesrc --group "$group" --key wmclass '(?i)^xwaylandvideobridge$'
    kwriteconfig6 --file kwinrulesrc --group "$group" --key acceptfocus false
    kwriteconfig6 --file kwinrulesrc --group "$group" --key acceptfocusrule 2
    kwriteconfig6 --file kwinrulesrc --group "$group" --key noborder true
    kwriteconfig6 --file kwinrulesrc --group "$group" --key noborderrule 2
    kwriteconfig6 --file kwinrulesrc --group "$group" --key opacityactive 0
    kwriteconfig6 --file kwinrulesrc --group "$group" --key opacityactiverule 2
    kwriteconfig6 --file kwinrulesrc --group "$group" --key opacityinactive 0
    kwriteconfig6 --file kwinrulesrc --group "$group" --key opacityinactiverule 2
    kwriteconfig6 --file kwinrulesrc --group "$group" --key skippager true
    kwriteconfig6 --file kwinrulesrc --group "$group" --key skippagerrule 2
    kwriteconfig6 --file kwinrulesrc --group "$group" --key skipswitcher true
    kwriteconfig6 --file kwinrulesrc --group "$group" --key skipswitcherrule 2
    kwriteconfig6 --file kwinrulesrc --group "$group" --key skiptaskbar true
    kwriteconfig6 --file kwinrulesrc --group "$group" --key skiptaskbarrule 2

    # kwinrulesrc [General] indexes the rule groups; append ours if missing and
    # keep count in step with the list.
    local rules newrules count
    rules="$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)"
    if [[ ",${rules}," != *",${group},"* ]]; then
        newrules="${rules:+$rules,}$group"
        kwriteconfig6 --file kwinrulesrc --group General --key rules "$newrules"
        count="$(awk -F, '{print NF}' <<<"$newrules")"
        kwriteconfig6 --file kwinrulesrc --group General --key count "$count"
    fi

    ok "KWin effects and window rules configured."
}

tweak_waydroid_apps() {
    info "Unhiding Waydroid Android apps..."
    local bundle="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local helper="${XDG_BIN_HOME:-$HOME/.local/bin}/caelestia-waydroid-apps"

    if [[ -f "$bundle/src/bin/caelestia-waydroid-apps" ]]; then
        mkdir -p "$(dirname "$helper")"
        install -m 0755 "$bundle/src/bin/caelestia-waydroid-apps" "$helper"
        # Waydroid marks the apps that ship with the image NoDisplay=true, and
        # Quickshell hides NoDisplay entries before the launcher ever sees them,
        # so without this the container's Android apps are simply absent.
        "$helper"
    else
        warn "Missing src/bin/caelestia-waydroid-apps - skipping."
    fi
}

tweak_kde_shortcuts() {
    info "Installing and applying global shortcuts..."
    local bundle="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local helper="${XDG_BIN_HOME:-$HOME/.local/bin}/caelestia-fix-shortcuts"

    if [[ -f "$bundle/src/bin/caelestia-fix-shortcuts" ]]; then
        mkdir -p "$(dirname "$helper")"
        install -m 0755 "$bundle/src/bin/caelestia-fix-shortcuts" "$helper"
    else
        warn "Missing src/bin/caelestia-fix-shortcuts - skipping."
        return 0
    fi

    # Shortcuts live in KWin's memory, not in a config file, so they can only
    # be written from inside a session. The helper stays installed for
    # re-applying after an update.
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v gdbus >/dev/null 2>&1; then
        if "$helper" >/dev/null 2>&1; then
            ok "Global shortcuts applied."
        else
            warn "caelestia-fix-shortcuts reported failures - run it manually to see details."
        fi
    else
        info "No session bus in this step - run '$helper' after logging in."
    fi
}

if [[ "${1:-}" == "--list" ]]; then
    echo
    echo "Available tweaks:"
    declare -F | awk '/^declare -f tweak_/ {print "  ", substr($3, 7)}' | sed 's/_/ /g'
    echo
    exit 0
fi

tweak_disable_kde_osd
tweak_five_desktops
tweak_remove_panels
tweak_no_splash_screen
tweak_default_shell
tweak_default_scheme
tweak_user_avatar_symlinks
tweak_kwin_scripts_and_effects
tweak_kde_shortcuts
tweak_waydroid_apps
# ---------------------------------------------------------------------------
# Material inspired icon theme.
#
# The Papirus set the installer used to pull in is Material Design 2 era
# artwork. Flat Remix keeps the Material look while looking closer to current
# Google designs; the theme lands in the user's own icon directory so it does
# not depend on a distribution package.
tweak_icon_theme() {
    local icons_dir="$HOME/.local/share/icons"
    local target="Flat-Remix-Violet-Dark"

    if [[ ! -d "$icons_dir/$target" ]]; then
        if command -v git >/dev/null 2>&1; then
            local tmp
            tmp="$(mktemp -d)"
            if git clone --depth 1 -q https://github.com/daniruiz/Flat-Remix.git "$tmp/flat-remix" 2>/dev/null; then
                mkdir -p "$icons_dir"
                cp -r "$tmp"/flat-remix/Flat-Remix* "$icons_dir"/ 2>/dev/null || true
            fi
            rm -rf "$tmp"
        fi
    fi

    if [[ -d "$icons_dir/$target" ]]; then
        kwriteconfig6 --file kdeglobals --group Icons --key Theme "$target" 2>/dev/null || true
        if command -v gsettings >/dev/null 2>&1; then
            gsettings set org.gnome.desktop.interface icon-theme "$target" 2>/dev/null || true
        fi
        ok "Icon theme set to $target."
    else
        warn "Could not install the Material icon theme; keeping the current one."
    fi
}

tweak_icon_theme
tweak_reload_kde


echo
ok "All system tweaks applied."
echo
