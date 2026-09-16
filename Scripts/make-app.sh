#!/bin/zsh
set -euo pipefail

# Creates a locally runnable, ad-hoc-signed app bundle in ./dist.
# Do not use this output for distribution; use a Developer ID certificate and notarization instead.
project_dir=${0:A:h:h}
output_dir="$project_dir/dist/Veycomm.app"
developer_dir=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

if [[ ! -d "$developer_dir" ]]; then
  print -u2 "Xcode was not found at $developer_dir. Install Xcode or set DEVELOPER_DIR."
  exit 1
fi

cd "$project_dir"
build_configuration=release
if ! DEVELOPER_DIR="$developer_dir" swift build -c "$build_configuration" --disable-sandbox; then
  # This is primarily useful in restricted CI sandboxes that block dSYM creation.
  # Debug output remains a fully runnable application bundle.
  print -u2 "Release build failed; creating a debug bundle instead."
  build_configuration=debug
  DEVELOPER_DIR="$developer_dir" swift build -c "$build_configuration" --disable-sandbox
fi
binary_dir=$(DEVELOPER_DIR="$developer_dir" swift build -c "$build_configuration" --disable-sandbox --show-bin-path)

if [[ -e "$output_dir" ]]; then
  print -u2 "Refusing to overwrite $output_dir. Move it aside before rebuilding."
  exit 1
fi

mkdir -p "$output_dir/Contents/MacOS" "$output_dir/Contents/Resources"
cp App/Info.plist "$output_dir/Contents/Info.plist"
release_version=${VERSION:-$(git describe --tags --always 2>/dev/null | sed 's/^v//')}
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $release_version" "$output_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $release_version" "$output_dir/Contents/Info.plist"
cp App/Assets/AppIcon.icns "$output_dir/Contents/Resources/AppIcon.icns"
cp "$binary_dir/Veycomm" "$output_dir/Contents/MacOS/Veycomm"
codesign --force --sign - "$output_dir"
print "Created $output_dir"
