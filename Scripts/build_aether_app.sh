#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
cd "$repo_dir"

skip_build=0
clean=0
for arg in "$@"; do
  case "$arg" in
    --skip-build) skip_build=1 ;;
    --clean) clean=1 ;;
    *) print -u2 "unknown flag: $arg (want --skip-build|--clean)"; exit 2 ;;
  esac
done

app_dir="$repo_dir/.build/Aether.app"
release_bin="$repo_dir/.build/release/AetherApp"
share_build_dir="$repo_dir/.build/share-extension"
share_bundle="$share_build_dir/Release/AetherShare.appex"

if (( clean )); then
  print "clean: deleting previous app + binary so stale code can never run"
  rm -rf "$app_dir" "$release_bin"
fi

if (( ! skip_build )); then
  nice -n 10 swift build -c release --jobs 1
  nice -n 10 xcodebuild -project Sources/AetherShare/AetherShare.xcodeproj \
    -target AetherShare -configuration Release -sdk macosx \
    SYMROOT="$share_build_dir" CODE_SIGNING_ALLOWED=NO build \
    > /tmp/aether-share-build.log 2>&1 || {
      rg 'error:|BUILD FAILED' /tmp/aether-share-build.log
      exit 1
    }
fi

[[ -f "$release_bin" ]] || { print -u2 "build produced no binary: $release_bin"; exit 1 }
[[ -f "$share_bundle/Contents/MacOS/AetherShare" ]] || {
  print -u2 "build produced no share extension: $share_bundle"; exit 1
}

icon_output=Sources/AetherApp/Resources/AetherIcon.icns
if [[ ! -f "$icon_output" ]] || [[ -n "$(find Sources/BrowserUI/Sources/icons -name '*.swift' -newer "$icon_output" -print -quit)" ]]; then
  "$repo_dir/Scripts/make_app_icon.sh"
fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/PlugIns"
cp "$release_bin" "$app_dir/Contents/MacOS/AetherApp"
cp Sources/AetherApp/Resources/Info.plist "$app_dir/Contents/Info.plist"
rm -rf "$app_dir/Contents/PlugIns/AetherShare.appex"
cp -R "$share_bundle" "$app_dir/Contents/PlugIns/AetherShare.appex"
if [[ -f Sources/AetherApp/Resources/AetherIcon.icns ]]; then
  cp Sources/AetherApp/Resources/AetherIcon.icns "$app_dir/Contents/Resources/AetherIcon.icns"
fi
for bundle in .build/release/*.bundle; do
  [[ -e "$bundle" ]] || continue
  cp -R "$bundle" "$app_dir/Contents/Resources/"
done

# Copy proof, BEFORE signing: the packaged binary must be bit-identical to the
# just-built release binary. (Checked here because `codesign --force` below
# legitimately rewrites the .app binary in place with its signature.)
sum_release=$(shasum -a 256 "$release_bin" | awk '{print $1}')
sum_app=$(shasum -a 256 "$app_dir/Contents/MacOS/AetherApp" | awk '{print $1}')
if [[ "$sum_release" != "$sum_app" ]]; then
  print -u2 "MISMATCH: .app binary differs from release binary before signing. Aborting."
  exit 1
fi
xattr -cr "$app_dir"
codesign --force --sign "${AETHER_SIGNING_IDENTITY:--}" --options runtime \
  --entitlements Sources/AetherShare/AetherShare.entitlements \
  "$app_dir/Contents/PlugIns/AetherShare.appex"
codesign --force --sign "${AETHER_SIGNING_IDENTITY:--}" --options runtime \
  --entitlements Sources/AetherApp/Resources/AetherApp.entitlements "$app_dir"
codesign --verify --strict "$app_dir"
codesign --verify --strict "$app_dir/Contents/PlugIns/AetherShare.appex"

# Freshness proof: the shipped binary must be at least as new as every source
# file. (Checked after signing, since signing refreshes the binary's mtime.)
newest_src=$(find Sources -name '*.swift' -print0 | xargs -0 stat -f '%m' | sort -n | tail -1)
bin_mtime=$(stat -f '%m' "$app_dir/Contents/MacOS/AetherApp")
if (( bin_mtime < newest_src )); then
  print -u2 "STALE BUILD: a .swift file is newer than the packaged binary. Aborting."
  exit 1
fi
sum_signed=$(shasum -a 256 "$app_dir/Contents/MacOS/AetherApp" | awk '{print $1}')
print "fresh: release sha256=$sum_release, signed app sha256=$sum_signed (newer than all sources)"
print "$app_dir"
