#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_SOURCE="$ROOT_DIR/config/Package.resolved"
LOCK_DEST="$ROOT_DIR/Mara.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

cd "$ROOT_DIR"
xcodegen generate
mkdir -p "${LOCK_DEST:h}"
cp "$LOCK_SOURCE" "$LOCK_DEST"

print "✅ Generated Mara.xcodeproj with locked SwiftPM revision."
