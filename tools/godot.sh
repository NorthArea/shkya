#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -n "${GODOT_BIN:-}" ]; then
    engine=$GODOT_BIN
elif [ -x "$repo/tools/local/Godot.app/Contents/MacOS/Godot" ]; then
    engine="$repo/tools/local/Godot.app/Contents/MacOS/Godot"
elif command -v godot >/dev/null 2>&1; then
    engine=$(command -v godot)
elif command -v godot4 >/dev/null 2>&1; then
    engine=$(command -v godot4)
elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    engine=/Applications/Godot.app/Contents/MacOS/Godot
else
    echo 'Нужен Godot 4.7.2. Укажите GODOT_BIN или установите Godot.app в /Applications.' >&2
    exit 1
fi
# Scripted checks are silent and windowless unless the owner requested a visible
# diagnostic. Keep this guard in the shared entry point, including direct calls.
scripted=0
for argument in "$@"; do
    case "$argument" in
        --) break ;;
        --script|-s|--script=*) scripted=1 ;;
    esac
done
if [ "$scripted" -eq 1 ] && [ "${GODOT_VISIBLE_CHECKS:-0}" != 1 ]; then
    # Insert last among engine options so earlier display/audio options cannot
    # override it; preserve everything after -- as the script's own arguments.
    remaining=$#
    inserted=0
    while [ "$remaining" -gt 0 ]; do
        argument=$1
        shift
        remaining=$((remaining - 1))
        if [ "$argument" = -- ] && [ "$inserted" -eq 0 ]; then
            set -- "$@" --headless --
            inserted=1
        else
            set -- "$@" "$argument"
        fi
    done
    if [ "$inserted" -eq 0 ]; then
        set -- "$@" --headless
    fi
fi
exec "$engine" "$@"
