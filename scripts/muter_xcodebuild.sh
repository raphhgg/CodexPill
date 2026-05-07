#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

/usr/bin/xcodebuild "$@"

for argument in "$@"; do
  if [[ "$argument" == "build-for-testing" ]]; then
    product_root="$PWD/Debug"
    mkdir -p "$product_root"
    while IFS= read -r xctestrun_path; do
      cp "$xctestrun_path" "$product_root/$(basename "$xctestrun_path")"
    done < <(find "$PWD" -path "*/Build/Products/*.xctestrun" -type f)
    break
  fi
done
