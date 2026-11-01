#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Runtime launches need the same texture imports as an editor launch.
prepare=1
scripted=0
explicit_window_mode=0
game_launch=1
for argument in "$@"; do
    case "$argument" in
        --) break ;;
        --editor|--import|--help|--version) prepare=0; game_launch=0 ;;
        --headless) game_launch=0 ;;
        --script|-s|--script=*) scripted=1 ;;
        --windowed|-w|--fullscreen|-f|--maximized|-m) explicit_window_mode=1 ;;
    esac
done
# godot.sh enforces background diagnostics even for direct script calls.
if [ "$scripted" -eq 1 ] && [ "$explicit_window_mode" -eq 0 ] && [ "${GODOT_VISIBLE_CHECKS:-0}" = 1 ]; then
    set -- --windowed "$@"
elif [ "$scripted" -eq 0 ] && [ "$game_launch" -eq 1 ] && [ "$explicit_window_mode" -eq 0 ]; then
    set -- --fullscreen "$@"
fi
if [ "$prepare" -eq 1 ]; then
    mkdir -p "$repo/builds"
    touch "$repo/builds/.gdignore"
    "$repo/tools/godot.sh" --path "$repo" --headless --editor --import
fi
exec "$repo/tools/godot.sh" --path "$repo" "$@"
