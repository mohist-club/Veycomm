#!/bin/zsh
set -euo pipefail

# Creates a drag-to-Applications disk image from the app bundle.
project_dir=${0:A:h:h}
app_path="$project_dir/dist/Veycomm.app"
dmg_path="$project_dir/dist/Veycomm.dmg"
staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT

if [[ ! -d "$app_path" ]]; then
  print -u2 "Missing $app_path. Run Scripts/make-app.sh first."
  exit 1
fi

ditto "$app_path" "$staging_dir/Veycomm.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname "Veycomm" -srcfolder "$staging_dir" -ov -format UDZO "$dmg_path"
print "Created $dmg_path"
