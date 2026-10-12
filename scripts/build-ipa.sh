#!/usr/bin/env bash
# Builds an unsigned Release .ipa for sideloading (Sideloadly signs it with the user's Apple ID).
set -euo pipefail

DERIVED=build/dd-device
mkdir -p build

xcodebuild build \
  -project Lumora.xcodeproj \
  -scheme Lumora \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  2>&1 | tee build/xcodebuild-ipa.log | bash scripts/beautify.sh

APP="$DERIVED/Build/Products/Release-iphoneos/Lumora.app"
if [ ! -d "$APP" ]; then
  echo "error: $APP not found" >&2
  exit 1
fi

rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry ../Lumora.ipa Payload)
ls -lh build/Lumora.ipa
