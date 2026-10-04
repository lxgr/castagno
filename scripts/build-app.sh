#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
export CLANG_MODULE_CACHE_PATH="$root/.build/clang-module-cache"
build_path=${CASTAGNO_BUILD_PATH:-"$root/.build"}
cp LICENSE Sources/Castagno/Resources/LICENSE
cp THIRD-PARTY-NOTICES.txt Sources/Castagno/Resources/THIRD-PARTY-NOTICES.txt
swift build --build-system native --scratch-path "$build_path" -c release --disable-sandbox
bin=$(swift build --build-system native --scratch-path "$build_path" -c release --show-bin-path --disable-sandbox)
app="$root/dist/Castagno.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Castagno" "$app/Contents/MacOS/Castagno.new"
mv -f "$app/Contents/MacOS/Castagno.new" "$app/Contents/MacOS/Castagno"
cp Vendor/SwiftyJSON/Source/SwiftyJSON/PrivacyInfo.xcprivacy "$app/Contents/Resources/PrivacyInfo.xcprivacy"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/Icons/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R "$bin/Castagno_Castagno.bundle" "$app/Contents/Resources/"
# Remove the old developer-only summary from previously built bundles.
rm -f "$app/Contents/Resources/Dependencies.md"
rm -f "$app/Contents/Resources/Castagno_Castagno.bundle/ChestnutSpeaker.png"
cp Vendor/OpenCastSwift/LICENSE "$app/Contents/Resources/OpenCastSwift-LICENSE"
cp Vendor/SwiftyJSON/LICENSE "$app/Contents/Resources/SwiftyJSON-LICENSE"
cp Vendor/SwiftProtobuf/LICENSE.txt "$app/Contents/Resources/SwiftProtobuf-LICENSE"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp THIRD-PARTY-NOTICES.txt "$app/Contents/Resources/THIRD-PARTY-NOTICES.txt"
cmp "$bin/Castagno" "$app/Contents/MacOS/Castagno"
codesign --force --sign "${CASTAGNO_SIGN_IDENTITY:--}" "$app"
touch "$app"
codesign --verify --deep --strict "$app"
printf 'Built at %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
printf 'Built %s\n' "$app"
shasum -a 256 "$app/Contents/MacOS/Castagno"
