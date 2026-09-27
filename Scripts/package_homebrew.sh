#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
app_dir="$repo_dir/.build/Aether.app"
output_dir="$repo_dir/.build/distribution"
info="$app_dir/Contents/Info.plist"

[[ -d "$app_dir" ]] || { print -u2 "Build Aether.app first with Scripts/build_aether_app.sh"; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")
mkdir -p "$output_dir" "$repo_dir/Casks"
dmg="$output_dir/Aether.dmg"
rm -f "$dmg"
hdiutil create -quiet -ov -format UDZO -volname Aether -srcfolder "$app_dir" "$dmg"
digest=$(shasum -a 256 "$dmg" | awk '{print $1}')
cat > "$repo_dir/Casks/aether.rb" <<EOF
cask "aether" do
  version "$version"
  sha256 "$digest"

  url "https://github.com/duggal1/aether/releases/download/v#{version}/Aether.dmg"
  name "Aether"
  desc "AI-native macOS browser"
  homepage "https://github.com/duggal1/aether"

  depends_on macos: ">= 27.0"
  app "Aether.app"
end
EOF

print "$dmg"
print "$repo_dir/Casks/aether.rb"
