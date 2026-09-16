#!/bin/zsh
set -euo pipefail

# Creates a drag-to-Applications disk image from the app bundle.
project_dir=${0:A:h:h}
app_path="$project_dir/dist/ShortcutShelf.app"
dmg_path="$project_dir/dist/ShortcutShelf.dmg"

if [[ ! -d "$app_path" ]]; then
  print -u2 "Missing $app_path. Run Scripts/make-app.sh first."
  exit 1
fi

hdiutil create -volname "ShortcutShelf" -srcfolder "$app_path" -ov -format UDZO "$dmg_path"
print "Created $dmg_path"
