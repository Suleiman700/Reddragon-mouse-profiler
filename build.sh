#!/usr/bin/env bash
# Builds dist/M901Mapper.exe with AutoHotkey's official compiler (Ahk2Exe).
# Usage:  bash build.sh [path-to-Ahk2Exe.exe]
set -euo pipefail
export MSYS2_ARG_CONV_EXCL='*'   # stop Git Bash from rewriting /in, /out, /base into file paths

ROOT="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
AHK2EXE="${1:-${AHK2EXE:-C:/Program Files/AutoHotkey/Compiler/Ahk2Exe.exe}}"
BASE="C:/Program Files/AutoHotkey/v2/AutoHotkey64.exe"

[ -f "$AHK2EXE" ] || { echo "Ahk2Exe not found: $AHK2EXE"; exit 1; }
[ -f "$ROOT/Lib/AutoHotInterception.ahk" ] || { echo "Lib/ is missing - see README setup"; exit 1; }

mkdir -p "$ROOT/dist"
"$AHK2EXE" /in "$ROOT/M901Mapper.ahk" /out "$ROOT/dist/M901Mapper.exe" /base "$BASE" /silent verbose
ls -l "$ROOT/dist"
