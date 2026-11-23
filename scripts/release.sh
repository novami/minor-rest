#!/bin/bash
# Sestaví Release (arm64), ad-hoc podepíše a vytvoří dist/MinorREST-<verze>-macos-arm64.zip + .zip.sig + .dmg.
# Použití: UPDATE_SIGNING_KEY=<base64> scripts/release.sh 0.3.5
set -euo pipefail
VERSION="${1:?verze ve tvaru MAJOR.MINOR.PATCH}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "neplatná verze: $VERSION" >&2; exit 1; }
cd "$(dirname "$0")/.."
DIST=dist; NAME="MinorREST-$VERSION-macos-arm64"
rm -rf "$DIST" .build/release-xcode && mkdir -p "$DIST"
xcodegen generate --quiet
xcodebuild -project MinorREST.xcodeproj -scheme MinorREST -configuration Release -derivedDataPath .build/release-xcode \
  MARKETING_VERSION="$VERSION" -quiet build
APP=.build/release-xcode/Build/Products/Release/MinorREST.app
codesign --force --deep -s - "$APP"
ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip"
hdiutil create -quiet -volname MinorREST -srcfolder "$APP" -format UDZO "$DIST/$NAME.dmg"
swift scripts/sign-update.swift --file "$DIST/$NAME.zip" > "$DIST/$NAME.zip.sig"
echo "hotovo: $DIST/"
