#!/bin/bash
# Builds a distributable TypingScape.app and zips it for handing to a tester.
#
# Ad-hoc signed (`--sign -`), not Developer ID — no Apple Developer account
# needed, at the cost of Gatekeeper warning the recipient on first launch
# (see README "테스트용으로 남에게 주기"). Upgrading later means swapping the
# identity here for a "Developer ID Application" cert and notarizing; the
# bundle layout doesn't change.
set -e
cd "$(dirname "$0")"

APP="dist/TypingScape.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift build -c release --arch arm64 --arch x86_64

cp .build/apple/Products/Release/TypingScape "$APP/Contents/MacOS/TypingScape"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Same keys as the dev build's linker-embedded plist, plus the bundle-only
# ones (icon, minimum system) that a bare executable has nowhere to put.
sed -e 's|</dict>|\
    <key>CFBundleIconFile</key>\
    <string>AppIcon</string>\
    <key>LSMinimumSystemVersion</key>\
    <string>14.0</string>\
</dict>|' Sources/TypingScape/Resources/Info.plist > "$APP/Contents/Info.plist"

# Accessibility/Input Monitoring grants are keyed to the signature, so a
# stable identifier keeps a tester's approval from being asked for twice.
codesign --force --deep --sign - --identifier "com.banshk.TypingScape" "$APP"
codesign --verify --verbose "$APP"

cd dist && zip -qr TypingScape.zip TypingScape.app && cd ..
echo
echo "완성: dist/TypingScape.zip"
echo "받는 사람은 압축을 풀고 README의 '테스트용으로 남에게 주기' 절대로 실행하면 됩니다."
