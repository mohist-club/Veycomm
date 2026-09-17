#!/bin/zsh
set -euo pipefail

# Uploads the DMG built and tested on this Mac. It intentionally never builds,
# repackages, or signs anything: the uploaded bytes are the bytes just tested.
project_dir=${0:A:h:h}
version=${1:-}
dmg_path="$project_dir/dist/Veycomm.dmg"

if [[ -z "$version" ]]; then
  print -u2 "Usage: Scripts/publish-local-release.sh 0.4.0"
  exit 2
fi
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "Version must look like 0.4.0"
  exit 2
fi
if [[ ! -f "$dmg_path" ]]; then
  print -u2 "Missing $dmg_path. Build and test the local DMG first."
  exit 1
fi
if ! hdiutil verify "$dmg_path"; then
  print -u2 "DMG verification failed; it was not uploaded."
  exit 1
fi
if git -C "$project_dir" diff --quiet; then
  :
else
  print -u2 "Working tree has uncommitted changes; commit the tested source first."
  exit 1
fi
if git -C "$project_dir" rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
  print -u2 "Tag v$version already exists."
  exit 1
fi

git -C "$project_dir" tag -a "v$version" -m "Veycomm $version"
git -C "$project_dir" push origin "v$version"
gh release create "v$version" "$dmg_path" --repo mohist-club/Veycomm --title "Veycomm $version" --generate-notes
print "Published the locally tested DMG: $dmg_path"
