#!/bin/sh
# This deliberately removes quarantine from Castagno only. It does not disable
# Gatekeeper or change any other extended attributes or system settings.
set -eu

if [ "$#" -gt 1 ]; then
    printf 'Usage: %s [path/to/Castagno.app]\n' "$0" >&2
    exit 2
fi
app=${1:-/Applications/Castagno.app}
if [ ! -d "$app" ] || [ "$(basename -- "$app")" != Castagno.app ]; then
    printf 'Expected a Castagno.app bundle: %s\n' "$app" >&2
    exit 1
fi
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
if [ "$identifier" != dev.castagno.app ]; then
    printf 'Refusing to modify a different app: %s\n' "$identifier" >&2
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/xattr -dr com.apple.quarantine "$app"
printf 'Removed quarantine from %s (ad hoc signed; not notarized).\n' "$app"
