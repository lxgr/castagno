#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary="$root/dist/Castagno.app/Contents/MacOS/Castagno"
if [ ! -x "$binary" ]; then
    printf 'Build Castagno first: %s/scripts/build-app.sh\n' "$root" >&2
    exit 1
fi
if [ "$#" -eq 0 ]; then
    set -- list
fi
exec "$binary" "$@"
