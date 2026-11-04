#!/usr/bin/env bash
# RealWorld — UX screenshots: desktop + phone (touch) [+ spawn screen] frames, plus a value report.
# Usage: tools/ux/shots.sh [godot-binary] [out-dir]     (needs xvfb-run; python3 with Pillow+numpy)
set -euo pipefail
G="${1:-godot}"; OUT="${2:-/tmp/rw-ux}"; mkdir -p "$OUT"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"$G" --headless --path "$ROOT/godot" --import >/dev/null 2>&1 || true
shot() { # name, extra args...
  local name="$1"; shift
  timeout 120 xvfb-run -a -s "-screen 0 1600x720x24" "$G" --path "$ROOT/godot" "$@" >/dev/null 2>&1 || true
  [ -f "$ROOT/godot/newhud_shot.png" ] && mv "$ROOT/godot/newhud_shot.png" "$OUT/$name.png"
}
shot desktop res://newhud.tscn -- newhud shot
shot touch --resolution 1600x720 res://newhud.tscn -- newhud shot touch scale=1.68
shot spawn res://newhud.tscn -- newhud shot spawn
python3 -I "$ROOT/tools/ux/value_check.py" "$OUT/desktop.png" "$OUT/value_desktop.png"
git -C "$ROOT" ls-files -o --exclude-standard | grep -E '\.png\.import$|newhud_thumb\.png$' | xargs -r rm -f
echo "shots → $OUT"
