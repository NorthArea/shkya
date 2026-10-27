#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Runtime launches need the same texture imports as an editor launch.
prepare=1
for argument in "$@"; do
    case "$argument" in
        --editor|--import|--help|--version) prepare=0 ;;
    esac
done
if [ "$prepare" -eq 1 ]; then
    mkdir -p "$repo/builds"
    touch "$repo/builds/.gdignore"
    "$repo/tools/godot.sh" --path "$repo" --headless --editor --import
fi
exec "$repo/tools/godot.sh" --path "$repo" "$@"
