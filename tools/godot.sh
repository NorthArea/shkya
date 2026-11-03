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
# A visible window does not authorize sound. Every launch is silent by default;
# real audio requires GODOT_ALLOW_AUDIO=1 for an explicitly authorized audio run.
scripted=0
fixed_fps_value=-1
fixed_fps_next=0
for argument in "$@"; do
    if [ "$fixed_fps_next" -eq 1 ]; then
        fixed_fps_value=$argument
        fixed_fps_next=0
        continue
    fi
    case "$argument" in
        --) break ;;
        --script|-s|--script=*) scripted=1 ;;
        --fixed-fps) fixed_fps_next=1 ;;
        --fixed-fps=*) fixed_fps_value=${argument#*=} ;;
    esac
done
# Godot consumes this engine flag before exposing OS.get_cmdline_args().
export GODOT_FIXED_FPS_WORKLOAD=0
if [ "$fixed_fps_value" -gt 0 ] 2>/dev/null; then
    export GODOT_FIXED_FPS_WORKLOAD=1
fi
background=0
if [ "$scripted" -eq 1 ] && [ "${GODOT_VISIBLE_CHECKS:-0}" != 1 ]; then
    background=1
fi
silent=1
if [ "${GODOT_ALLOW_AUDIO:-0}" = 1 ]; then
    silent=0
fi
if [ "$background" -eq 1 ] || [ "$silent" -eq 1 ]; then
    # Insert last among engine options so earlier display/audio options cannot
    # override it; preserve everything after -- as the script's own arguments.
    remaining=$#
    inserted=0
    while [ "$remaining" -gt 0 ]; do
        argument=$1
        shift
        remaining=$((remaining - 1))
        if [ "$argument" = -- ] && [ "$inserted" -eq 0 ]; then
            if [ "$background" -eq 1 ]; then
                set -- "$@" --headless
            fi
            if [ "$silent" -eq 1 ]; then
                set -- "$@" --audio-driver Dummy
            fi
            set -- "$@" --
            inserted=1
        else
            set -- "$@" "$argument"
        fi
    done
    if [ "$inserted" -eq 0 ]; then
        if [ "$background" -eq 1 ]; then
            set -- "$@" --headless
        fi
        if [ "$silent" -eq 1 ]; then
            set -- "$@" --audio-driver Dummy
        fi
    fi
fi
exec "$engine" "$@"
