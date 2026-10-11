#!/usr/bin/env bash
set -euo pipefail

# macOS can't switch a bundle's icon at runtime, so each alternate colour ships
# as a PNG that the app sets as its in-app icon. Rerun after editing an .icon.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICTOOL="${ICTOOL:-/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool}"
OUTPUT_DIR="$ROOT_DIR/Resources/AppIconColors"

# ictool renders the squircle edge to edge. macOS draws app icons at 824/1024
# of the canvas, so pad the render to match the bundle icon in alerts.
render() {
  "$ICTOOL" "$1" --export-image --output-file "$2" \
    --platform macOS --rendition Default --width 103 --height 103 --scale 2 >/dev/null
  sips --padToHeightWidth 256 256 "$2" >/dev/null
}

mkdir -p "$OUTPUT_DIR"
for icon in "$ROOT_DIR"/Design/AppIconColors/*.icon; do
  color="$(basename "$icon" .icon)"
  render "$icon" "$OUTPUT_DIR/AppIcon-$color.png"
done

render "$ROOT_DIR/Resources/AppIcon.icon" "$ROOT_DIR/docs/images/app-icon.png"
