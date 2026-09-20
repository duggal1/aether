#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
cd "$repo_dir"
if [[ "${1:-}" != "--skip-build" ]]; then
  nice -n 10 swift build -c release --jobs 1
fi
icon_output=Sources/AetherApp/Resources/AetherIcon.icns
if [[ ! -f "$icon_output" ]] || [[ -n "$(find Sources/BrowserUI/Sources/icons -name '*.swift' -newer "$icon_output" -print -quit)" ]]; then
  "$repo_dir/Scripts/make_app_icon.sh"
fi
app_dir="$repo_dir/.build/Aether.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/AetherApp "$app_dir/Contents/MacOS/AetherApp"
cp Sources/AetherApp/Resources/Info.plist "$app_dir/Contents/Info.plist"
if [[ -f Sources/AetherApp/Resources/AetherIcon.icns ]]; then
  cp Sources/AetherApp/Resources/AetherIcon.icns "$app_dir/Contents/Resources/AetherIcon.icns"
fi
for bundle in .build/release/*.bundle; do
  [[ -e "$bundle" ]] || continue
  cp -R "$bundle" "$app_dir/Contents/Resources/"
done
xattr -cr "$app_dir"
codesign --force --sign "${AETHER_SIGNING_IDENTITY:--}" --options runtime \
  --entitlements Sources/AetherApp/Resources/AetherApp.entitlements "$app_dir"
codesign --verify --strict "$app_dir"
print "$app_dir"
