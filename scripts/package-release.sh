#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
if [ "$(uname -m)" != arm64 ]; then
    printf 'Castagno releases are Apple Silicon only; build on an arm64 Mac.\n' >&2
    exit 1
fi
./scripts/build-app.sh
app="$root/dist/Castagno.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
case "$version" in
    ''|*[!0-9.]*) printf 'Unexpected app version: %s\n' "$version" >&2; exit 1 ;;
esac
architectures=$(/usr/bin/lipo -archs "$app/Contents/MacOS/Castagno")
if [ "$architectures" != arm64 ]; then
    printf 'Expected an arm64-only executable, got: %s\n' "$architectures" >&2
    exit 1
fi
stage=$(mktemp -d "$root/dist/release.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
/usr/bin/ditto --norsrc --noqtn "$app" "$stage/Castagno.app"
cp scripts/allow-castagno.sh "$stage/allow-castagno.sh"
/usr/bin/codesign --verify --deep --strict "$stage/Castagno.app"
archive="$root/dist/Castagno-$version-macos-arm64.zip"
/usr/bin/ditto -c -k --norsrc --noqtn "$stage" "$archive"
cd "$root/dist"
shasum -a 256 "$(basename "$archive")" > SHA256SUMS
printf 'Packaged %s\n' "$archive"
cat SHA256SUMS
