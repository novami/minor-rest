#!/bin/bash
# Lokální vydání: Release build (arm64), ad-hoc podpis, zip, podepsaný appcast.json (sdílený klíč MinorUpdate z Keychainu).
# Použití: scripts/release.sh 0.3.5      (privátní klíč nikdy neopouští Mac)
set -euo pipefail
VERSION="${1:?verze ve tvaru MAJOR.MINOR.PATCH}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "neplatná verze: $VERSION" >&2; exit 1; }
cd "$(dirname "$0")/.."
[ -z "$(git status --porcelain)" ] || { echo "pracovní strom není čistý" >&2; exit 1; }
DIST=dist; NAME="MinorREST-$VERSION"
rm -rf "$DIST" .build/release-xcode && mkdir -p "$DIST"
xcodegen generate --quiet
xcodebuild -project MinorREST.xcodeproj -scheme MinorREST -configuration Release -derivedDataPath .build/release-xcode \
  MARKETING_VERSION="$VERSION" -quiet build
APP=.build/release-xcode/Build/Products/Release/MinorREST.app
codesign --force --deep -s - "$APP"
ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip"
URL="https://github.com/novami/minor-rest/releases/download/$VERSION/$NAME.zip"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")
NOTES="docs/release-notes/$VERSION.md"
if [ -f "$NOTES" ]; then
  swift scripts/minorupdate.swift sign "$DIST/$NAME.zip" "$BUNDLE_ID" "$VERSION" "$URL" "$NOTES" > "$DIST/appcast.json"
else
  swift scripts/minorupdate.swift sign "$DIST/$NAME.zip" "$BUNDLE_ID" "$VERSION" "$URL" > "$DIST/appcast.json"
fi
echo "Hotovo: $DIST/. Publikace (po tagu $VERSION a pushi, jen na pokyn):"
echo "  gh release create $VERSION $DIST/$NAME.zip $DIST/appcast.json --title $VERSION --generate-notes"
