#!/usr/bin/env sh
#
# Run a desktop script inside a terminal window.
#
# Shortcuts that point at a shell script are meant to be watched, so this is
# launched by the terminal emulator as its command: the script is started from
# its own directory (relative paths inside it keep working) and the window is
# kept open afterwards, otherwise a failing script would flash by unseen.

set -u

script="${1:-}"

if [ -z "$script" ] || [ ! -f "$script" ]; then
    printf 'No such script: %s\n' "$script" >&2
    status=127
else
    dir="$(dirname -- "$script")"
    base="$(basename -- "$script")"

    if ! cd -- "$dir"; then
        printf 'Cannot enter %s\n' "$dir" >&2
        status=1
    else
        printf '\033[1;32m==> %s\033[0m\n\n' "$script"

        if [ -x "$script" ]; then
            "./$base"
        else
            sh "./$base"
        fi
        status=$?

        printf '\n\033[1;33m[%s exited with status %d]\033[0m\n' "$base" "$status"
    fi
fi

# Keep the window open so the output stays readable (only makes sense when the
# script actually runs in a terminal).
if [ -t 0 ]; then
    printf 'Press Enter to close... '
    read -r _
fi

exit "$status"
