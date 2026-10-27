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
exec "$engine" "$@"
