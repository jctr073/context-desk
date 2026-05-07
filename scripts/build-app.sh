#!/bin/zsh
set -euo pipefail

APP_NAME="ContextDesk"
PROJECT_FILE="ContextDesk.xcodeproj"
SCHEME="ContextDesk"
CONFIGURATION="${CONFIGURATION:-Release}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode"
EXPORT_DIR="$ROOT_DIR/.build/app"
APP_DIR="$EXPORT_DIR/$APP_NAME.app"
BUILT_APP="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
ICONSET_DIR="$ROOT_DIR/.build/app-icon.iconset"
ICNS_PATH="$ROOT_DIR/.build/$APP_NAME.icns"

cd "$ROOT_DIR"

mkdir -p "$ROOT_DIR/.build/module-cache" "$DERIVED_DATA_DIR" "$EXPORT_DIR"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export MODULE_CACHE_DIR="$ROOT_DIR/.build/module-cache"

xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build

if [[ ! -d "$BUILT_APP" ]]; then
    echo "Expected app bundle was not created: $BUILT_APP" >&2
    exit 1
fi

rm -rf "$APP_DIR"
ditto "$BUILT_APP" "$APP_DIR"

if command -v swift >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    swift "$ROOT_DIR/scripts/create-icon.swift" "$ICONSET_DIR"
    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
    cp "$ICNS_PATH" "$APP_DIR/Contents/Resources/$APP_NAME.icns"

    if /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $APP_NAME" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1; then
        :
    else
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $APP_NAME" "$APP_DIR/Contents/Info.plist"
    fi
else
    echo "Skipping icon generation because swift or iconutil is unavailable." >&2
fi

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "$APP_DIR"
