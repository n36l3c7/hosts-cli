#!/usr/bin/env bash
#
# Record demo/session.sh into docs/demo.gif.
#
# The recipe is kept in the repository rather than the result being produced by
# hand once, so that when the output of a command changes the picture of it can
# be regenerated instead of quietly becoming a lie.
#
# Needs asciinema and agg, neither of which is a dependency of the program:
#
#   curl -fsSLo ~/.local/bin/asciinema \
#     https://github.com/asciinema/asciinema/releases/download/v3.2.1/asciinema-x86_64-unknown-linux-musl
#   curl -fsSLo ~/.local/bin/agg \
#     https://github.com/asciinema/agg/releases/download/v1.9.0/agg-x86_64-unknown-linux-musl
#   chmod +x ~/.local/bin/asciinema ~/.local/bin/agg

set -euo pipefail

readonly THEME=${THEME:-nord}
readonly FONT=${FONT:-DejaVu Sans Mono}
readonly FONT_SIZE=${FONT_SIZE:-16}
readonly FPS=${FPS:-12}

# Sized to the session rather than to whatever terminal does the recording.
# 61 columns is the longest line and 22 rows the whole session, so nothing
# scrolls away and nothing is framed by a wide margin of empty background.
readonly WINDOW=${WINDOW:-66x24}

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output=${1:-$root/docs/demo.gif}

for tool in asciinema agg; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'demo: %s is not on PATH; see the comment at the top of this file\n' \
      "$tool" >&2
    exit 1
  fi
done

make -C "$root" build >/dev/null

workspace=$(mktemp -d)
trap 'rm -rf -- "$workspace"' EXIT INT TERM

# The recorded session calls "hosts", and this is the copy it gets: the one
# just built from these sources, not whatever happens to be installed.
mkdir -p "$workspace/bin" "$workspace/demo"
cp "$root/build/hosts" "$workspace/bin/hosts"
cp "$root/demo/session.sh" "$workspace/demo/session.sh"
chmod +x "$workspace/bin/hosts" "$workspace/demo/session.sh"

cast="$workspace/demo.cast"

# The backup store goes in the workspace too. A demo has no business writing
# into /var/backups, and none into the store of whoever is recording it.
(
  cd "$workspace/demo"
  PATH="$workspace/bin:$PATH" \
    HOSTS_BACKUP_DIR="$workspace/backups" \
    HOSTS_PROFILE_DIR="$workspace/profiles" \
    asciinema rec --overwrite --quiet \
    --window-size "$WINDOW" \
    --command "$workspace/demo/session.sh" \
    "$cast"
)

printf -- '--- recorded ---\n'
head -1 "$cast"

mkdir -p "$(dirname -- "$output")"
agg \
  --theme "$THEME" \
  --font-family "$FONT" \
  --font-size "$FONT_SIZE" \
  --fps-cap "$FPS" \
  "$cast" "$output"

printf -- '\n--- %s ---\n' "$output"
ls -lh "$output" | awk '{print $5, $9}'
