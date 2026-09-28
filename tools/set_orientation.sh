#!/usr/bin/env bash
# Set the phone orientation (desktop is always landscape 1920x1080, see scripts/autoload/platform.gd).
# Usage: tools/set_orientation.sh portrait|landscape
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$PROJECT_DIR/project.godot"

case "${1:-}" in
	portrait)  ORIENT=1 ;; # portrait: phone UI 720x1280
	landscape) ORIENT=4 ;; # sensor landscape (either side up): phone UI 1280x720
	*) echo "Usage: $0 portrait|landscape" >&2; exit 1 ;;
esac

perl -pi -e "s|^window/handheld/orientation=.*|window/handheld/orientation=$ORIENT|;" "$CFG"

echo "Phone orientation set to $1."
