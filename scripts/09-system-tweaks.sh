#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/virtual-desktops.sh"
# shellcheck source=scripts/lib/plasmazones.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/plasmazones.sh"

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
    ensure_five_virtual_desktops
}

tweak_remove_panels() {
    if ! first_install; then
        skip "Not a first install - leaving Plasma panels alone."
    else
        info "Removing KDE Plasma panels..."

        if qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
            "var p = panels(); for (var i = 0; i < p.length; i++) { p[i].remove(); }" \
            2>/dev/null; then
            ok "KDE panels removed."
        else
            remove_panels_from_config || warn "Failed to remove KDE panels from config."
            ok "KDE panels removed."
        fi
    fi

    hide_kde_desktop_icons
}

remove_panels_from_config() {
    python3 - <<'EOF'
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
}

# The desktop containment is a Folder View: it draws ~/Desktop itself. Caelestia
# draws those icons too, so the two layers overlap and Plasma wins because it is
# the actual desktop. Point the Folder View at an empty directory so Plasma keeps
# the wallpaper while Caelestia supplies the icons.
#
# Plasmashell keeps the setting in memory and only writes it back on a clean
# exit, so a crash (or an upgrade that migrates the containment) brings the
# duplicate icons back. The fix therefore ships as a helper that updates the
# running shell *and* the config file, plus a user unit and a plasmashell
# drop-in that both re-assert it - at login and after every plasmashell start.
DESKTOP_ICONS_EMPTY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/caelestia/empty-desktop"
DESKTOP_ICONS_EMPTY_URL="file://$DESKTOP_ICONS_EMPTY_DIR"
DESKTOP_ICONS_HELPER="$HOME/.local/bin/caelestia-hide-kde-desktop-icons"
DESKTOP_ICONS_UNIT="$HOME/.config/systemd/user/caelestia-desktop-icons-guard.service"
DESKTOP_ICONS_DROPIN="$HOME/.config/systemd/user/plasma-plasmashell.service.d/10-caelestia-desktop-icons.conf"

write_desktop_icons_guard() {
    mkdir -p "${DESKTOP_ICONS_HELPER%/*}" "$HOME/.config/systemd/user" "${DESKTOP_ICONS_DROPIN%/*}"

    cat > "$DESKTOP_ICONS_HELPER" << 'HELPER'
#!/usr/bin/env bash
# Keep Plasma's desktop Folder View pointed at an empty directory: Caelestia
# draws the desktop icons itself, so anything Plasma draws there is a duplicate.
# Updates the running plasmashell (so it takes effect now) and the containment
# config (so a crash, which skips plasmashell's own save, cannot undo it).
set -uo pipefail

empty_dir="${XDG_DATA_HOME:-$HOME/.local/share}/caelestia/empty-desktop"
empty_url="file://$empty_dir"
config="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
mkdir -p "$empty_dir"

# Prints "desktops=N ok=M" back through evaluateScript, which is the only way to
# tell whether the desktops existed yet and whether the write took.
js="var d = desktops(); var ok = 0; for (var i = 0; i < d.length; i++) { var c = d[i]; c.currentConfigGroup = ['General']; if (c.readConfig('url', '') !== '$empty_url') { c.writeConfig('url', '$empty_url'); c.writeConfig('labelMode', 0); c.reloadConfig(); } if (c.readConfig('url', '') === '$empty_url') ok++; } print('desktops=' + d.length + ' ok=' + ok);"

for _ in 1 2 3 4 5; do
    out="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$js" 2>/dev/null || true)"
    n="${out#*desktops=}"
    n="${n%% *}"
    m="${out#*ok=}"
    m="${m%% *}"
    if [[ "$n" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]] && ((n > 0 && n == m)); then
        break
    fi
    sleep 2
done

# Keep the file in step as well.
python3 - "$empty_url" "$config" << 'PY' >/dev/null 2>&1 || true
import os
import re
import sys

url = sys.argv[1]
path = sys.argv[2]
if not os.path.exists(path):
    raise SystemExit(0)

lines = open(path, "r", encoding="utf-8").read().splitlines()

desktop_id = None
current = None
formfactor = None
plugin = None
DESKTOP_PLUGINS = ("org.kde.desktopcontainment", "org.kde.plasma.folder", "org.kde.plasma.desktop")

def is_desktop_containment():
    return formfactor == "0" and plugin in DESKTOP_PLUGINS

for line in lines:
    s = line.strip()
    m = re.match(r"^\[Containments\]\[(\d+)\]$", s)
    if m:
        current = m.group(1)
        formfactor = None
        plugin = None
        continue
    if s.startswith("["):
        # Applet subgroups carry their own formfactor/plugin pairs, which must
        # not be mistaken for the desktop containment itself.
        current = None
        continue
    if current is None:
        continue
    if s.startswith("formfactor="):
        formfactor = s.split("=", 1)[1].strip()
    elif s.startswith("plugin="):
        plugin = s.split("=", 1)[1].strip()
    if desktop_id is None and is_desktop_containment():
        desktop_id = current

if desktop_id is None:
    raise SystemExit(0)

general = f"[Containments][{desktop_id}][Configuration][General]"
out = []
seen_general = False
in_general = False
for line in lines:
    s = line.strip()
    if s == general:
        seen_general = True
        in_general = True
        out.append(line)
        out.append(f"url={url}")
        out.append("labelMode=0")
        continue
    if in_general:
        if s.startswith("["):
            in_general = False
            out.append(line)
        elif s.startswith("url=") or s.startswith("labelMode="):
            continue
        else:
            out.append(line)
        continue
    out.append(line)

if not seen_general:
    out.append("")
    out.append(general)
    out.append(f"url={url}")
    out.append("labelMode=0")

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print("KDE desktop icons hidden in the containment config")
PY

# Plasma has not written its configuration yet (first install): the drop-in
# and the unit take care of the first session.
[[ -f "$config" ]] || exit 0

grep -qx "url=$empty_url" "$config" 2>/dev/null
HELPER
    chmod +x "$DESKTOP_ICONS_HELPER"

    cat > "$DESKTOP_ICONS_UNIT" << UNIT
[Unit]
Description=Keep Plasma's desktop folder view empty (Caelestia draws the icons)
After=plasma-plasmashell.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$DESKTOP_ICONS_HELPER

[Install]
WantedBy=default.target
UNIT

    cat > "$DESKTOP_ICONS_DROPIN" << UNIT
[Service]
ExecStartPost=$DESKTOP_ICONS_HELPER
UNIT

    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable caelestia-desktop-icons-guard.service >/dev/null 2>&1 || true
}

hide_kde_desktop_icons() {
    write_desktop_icons_guard

    if "$DESKTOP_ICONS_HELPER"; then
        ok "KDE desktop icons hidden (Caelestia draws them)."
        return 0
    fi

    warn "Failed to hide the KDE desktop icons."
    return 1
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

tweak_shell_prefs() {
    local assets="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/scripts/assets"

    if [[ -f "$assets/shell-prefs.json" ]]; then
        python3 - "$assets/shell-prefs.json" <<'PYEOF'
import json
import os
import sys

prefs = json.load(open(sys.argv[1]))
path = os.path.expanduser("~/.config/caelestia/shell.json")
current = {}
if os.path.exists(path):
    current = json.load(open(path))

def merge(base, override):
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge(base[key], value)
        else:
            base[key] = value

def expand_strings(node):
    # Values may carry "$HOME" (e.g. the tray icon cache path), including
    # inside lists, so walk the whole merged tree before writing.
    if isinstance(node, dict):
        return {k: expand_strings(v) for k, v in node.items()}
    if isinstance(node, list):
        return [expand_strings(v) for v in node]
    if isinstance(node, str):
        return os.path.expandvars(os.path.expanduser(node))
    return node

json.dump(expand_strings(current), open(path, "w"), indent=4, ensure_ascii=False)
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(current, open(path, "w"), indent=4, ensure_ascii=False)
print("shell.json preferences merged.")
PYEOF
        ok "Caelestia shell preferences applied."
    else
        warn "scripts/assets/shell-prefs.json missing; shell preferences skipped."
    fi

    if [[ -f "$assets/keybinds-prefs.json" ]]; then
        python3 - "$assets/keybinds-prefs.json" <<'PYEOF'
import json
import os
import sys

prefs = json.load(open(sys.argv[1]))
path = os.path.expanduser("~/.config/caelestia/keybinds.json")
current = {}
if os.path.exists(path):
    current = json.load(open(path))
current.update(prefs)
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(current, open(path, "w"), indent=4, ensure_ascii=False)
print("keybinds.json preferences merged.")
PYEOF
        ok "Caelestia keybind preferences applied."
    fi
}

tweak_material_you_colors() {
    local venv="$HOME/.local/share/caelestia-venvs/kde-material-you-colors"
    local bin="$HOME/.local/bin/kde-material-you-colors"

    if ! python3 -c "import dbus" 2>/dev/null; then
        warn "python3-dbus is missing; install it (dnf install python3-dbus python3-pillow) for kde-material-you-colors."
        return
    fi

    if [[ ! -x "$bin" ]]; then
        info "Installing kde-material-you-colors..."
        python3 -m venv --system-site-packages "$venv" || { warn "venv creation failed."; return; }
        "$venv/bin/pip" install -q --upgrade pip >/dev/null 2>&1 || true
        "$venv/bin/pip" install -q kde-material-you-colors pywal16 || { warn "pip install failed."; return; }
        ln -sfn "$venv/bin/kde-material-you-colors" "$bin"
        ok "kde-material-you-colors installed."
    fi

    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/kde-material-you-colors.desktop" <<EOF
[Desktop Entry]
Categories=Utility;
Comment=Automatic color scheme generator from wallpaper
Exec=$bin --autostart
GenericName=Color generator
Icon=kde-material-you-colors
Name=KDE Material You Colors
StartupNotify=false
Terminal=false
Type=Application
X-KDE-StartupNotify=false
EOF
    ok "kde-material-you-colors autostart installed."
}

tweak_cursor_theme() {
    local icons_dir="$HOME/.local/share/icons"
    local target="Bibata-Modern-Classic"
    local url="https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata-Modern-Classic.tar.xz"

    if [[ ! -d "$icons_dir/$target" ]]; then
        if command -v curl >/dev/null 2>&1; then
            local tmp
            tmp="$(mktemp -d)"
            if curl -sL -o "$tmp/bibata.tar.xz" "$url" 2>/dev/null; then
                tar -xf "$tmp/bibata.tar.xz" -C "$tmp" 2>/dev/null
                if [[ -d "$tmp/$target" ]]; then
                    mkdir -p "$icons_dir"
                    cp -r "$tmp/$target" "$icons_dir/"
                    ok "Bibata cursor theme installed."
                fi
            fi
            rm -rf "$tmp"
        fi
    fi

    if [[ -d "$icons_dir/$target" ]]; then
        kwriteconfig6 --file kdeglobals --group General --key CursorTheme "$target" 2>/dev/null || true
        if command -v gsettings >/dev/null 2>&1; then
            gsettings set org.gnome.desktop.interface cursor-theme "$target" 2>/dev/null || true
        fi
        mkdir -p "$HOME/.icons/default"
        printf "[Icon Theme]\nName=Default\nInherits=%s\n" "$target" > "$HOME/.icons/default/index.theme"
        ok "Cursor theme set to $target."
    else
        warn "Could not install the Bibata cursor theme; keeping the current one."
    fi
}

tweak_icon_theme() {
    local icons_dir="$HOME/.local/share/icons"
    local target="WhiteSur-dark"
    local repo="https://github.com/vinceliuice/WhiteSur-icon-theme.git"

    if [[ ! -d "$icons_dir/$target" ]]; then
        if command -v git >/dev/null 2>&1; then
            local tmp
            tmp="$(mktemp -d)"
            if git clone --depth 1 -q "$repo" "$tmp/whitesur" 2>/dev/null; then
                mkdir -p "$icons_dir"
                if [[ -x "$tmp/whitesur/install.sh" ]]; then
                    (cd "$tmp/whitesur" && ./install.sh -d "$icons_dir" >/dev/null 2>&1) || true
                fi
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
        warn "Could not install the WhiteSur icon theme; keeping the current one."
    fi
}

tweak_kwin_scripts_and_effects() {
    local bundle="${BUNDLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local scripts_root="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts"
    local script

    # dwmove is the renamed dynamicworkspaces (new plugin Id: KWin caches the
    # compiled QML by URL, so a session that already loaded the old Id keeps
    # running the old code until logout either way).
    local old_dst="$scripts_root/dynamicworkspaces"
    if [[ -d "$old_dst" ]]; then
        # Upgraded from the pre-rename layout: retire the old plugin so both
        # instances never run their recycle logic at once.
        info "Retiring pre-rename dynamicworkspaces plugin..."
        kwriteconfig6 --file kwinrc --group Plugins --key dynamicworkspacesEnabled false 2>/dev/null || true
        rm -rf "$old_dst" 2>/dev/null || true
    fi

    for script in dwmove genieshowdesktop; do
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
    kwriteconfig6 --file kwinrc --group Plugins --key dwmoveEnabled true 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group Plugins --key genieshowdesktopEnabled true 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group Plugins --key magiclampEnabled true 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group Plugins --key squashEnabled false 2>/dev/null || true
    # This setup's look: Caelestia draws its own blur, so KWin's is off.
    kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group Plugins --key glassEnabled true 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled false 2>/dev/null || true
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

tweak_input_method() {
    # A Fedora Wayland session inherits the X11-only "no input method" profile
    # (QT_IM_MODULE=xim, XMODIFIERS=@im=none, GTK_IM_MODULE=gtk-im-context-simple),
    # and the systemd user manager then hands those variables to every unit it
    # starts. On Wayland fcitx5 reaches clients through the compositor's
    # text-input protocol instead, and an application told to use
    # gtk-im-context-simple never talks to fcitx5 at all, so its text fields stay
    # inert. Clearing the variables is the documented Wayland configuration.
    info "Pointing the session at fcitx5's Wayland text-input path..."

    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"

    # Plasma sources /etc/xdg/plasma-workspace/env/*.sh first and this directory
    # last, so the unset wins whichever profile the distribution exported.
    local env_dir="$cfg/plasma-workspace/env"
    mkdir -p "$env_dir"
    cat >"$env_dir/20-fcitx5-wayland.sh" <<'ENVEOF'
#!/bin/sh
# Caelestia: give the session fcitx5's Wayland text-input path.
#
# A Fedora Wayland session inherits the X11-only "no input method" profile
# (QT_IM_MODULE=xim, XMODIFIERS=@im=none, GTK_IM_MODULE=gtk-im-context-simple).
# On Wayland fcitx5 reaches applications through the compositor instead, and GTK
# applications told to use gtk-im-context-simple never talk to it at all, so
# nothing composes. Plasma sources the system directory before this one, so
# clearing the variables here wins for the whole session.
unset QT_IM_MODULE XMODIFIERS GTK_IM_MODULE SDL_IM_MODULE GLFW_IM_MODULE
ENVEOF
    chmod 0755 "$env_dir/20-fcitx5-wayland.sh"
    ok "Session input-method environment cleaned: $env_dir/20-fcitx5-wayland.sh"

    # The shell has to be fixed now rather than at the next login: the systemd
    # user manager keeps the stale variables in its own environment and passes
    # them to every unit it starts, so the unit drops them itself.
    local unit_dir="$cfg/systemd/user/caelestia-shell.service.d"
    mkdir -p "$unit_dir"
    cat >"$unit_dir/20-input-method.conf" <<'UNITEOF'
[Unit]
Description=Use the Wayland text-input path for the shell (fcitx5 IME)

[Service]
UnsetEnvironment=QT_IM_MODULE XMODIFIERS GTK_IM_MODULE SDL_IM_MODULE GLFW_IM_MODULE
UNITEOF

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
        if systemctl --user is-active --quiet caelestia-shell.service 2>/dev/null; then
            systemctl --user restart caelestia-shell.service 2>/dev/null || true
        fi
    fi
    ok "Caelestia shell runs without the X11 input-method variables."
}

tweak_plasmazones() {
    plasmazones_setup
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
tweak_shell_prefs
tweak_material_you_colors
tweak_icon_theme
tweak_cursor_theme
tweak_input_method
tweak_plasmazones
tweak_reload_kde

echo
ok "All system tweaks applied."
echo
