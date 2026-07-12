#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MotionSpec"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RELEASE_DIR="$ROOT_DIR/release"
DMG_STAGING_DIR="$ROOT_DIR/dist/dmg"
# The public repository artifact is release/MotionSpec.dmg.
DMG_PATH="$RELEASE_DIR/$APP_NAME.dmg"
ICON_SOURCE="$ROOT_DIR/logo.png"
ICONSET_DIR="$ROOT_DIR/dist/$APP_NAME.iconset"
ICON_PATH="$ROOT_DIR/dist/$APP_NAME.icns"
CONFIG_FILE="${MOTIONSPEC_PACKAGE_CONFIG:-$ROOT_DIR/.motionspec-package.env}"

strip_optional_quotes() {
  local value="$1"

  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value#\"}"
    value="${value%\"}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value#\'}"
    value="${value%\'}"
  fi

  printf '%s' "$value"
}

set_config_value_unless_exported() {
  local name="$1"
  local value="$2"

  if [[ -z "${!name:-}" ]]; then
    printf -v "$name" '%s' "$value"
    export "$name"
  fi
}

load_local_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    case "$line" in
      CODESIGN_IDENTITY=*)
        set_config_value_unless_exported \
          "CODESIGN_IDENTITY" \
          "$(strip_optional_quotes "${line#CODESIGN_IDENTITY=}")"
        ;;
      MOTIONSPEC_ADHOC_SIGN=*)
        set_config_value_unless_exported \
          "MOTIONSPEC_ADHOC_SIGN" \
          "$(strip_optional_quotes "${line#MOTIONSPEC_ADHOC_SIGN=}")"
        ;;
    esac
  done < "$CONFIG_FILE"
}

sign_app() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "Signing $APP_DIR with identity: $CODESIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp=none \
      --sign "$CODESIGN_IDENTITY" \
      "$APP_DIR"
    return
  fi

  if [[ "${MOTIONSPEC_ADHOC_SIGN:-0}" == "1" ]]; then
    echo "Ad-hoc signing $APP_DIR"
    codesign --force --deep --sign - "$APP_DIR"
    return
  fi

  cat <<EOF
Skipping codesign. To keep macOS permissions stable between rebuilds:
  security find-identity -v -p codesigning
  echo 'CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"' > "$CONFIG_FILE"
Or create a local development signing identity:
  bash scripts/setup_local_signing.sh
Then rebuild with:
  bash scripts/package_app.sh
EOF
}

create_app_icon() {
  [[ -f "$ICON_SOURCE" ]] || {
    echo "Missing app icon source: $ICON_SOURCE" >&2
    exit 1
  }

  local dimensions
  dimensions="$(sips -g pixelWidth -g pixelHeight "$ICON_SOURCE")"
  if ! grep -Fq "pixelWidth: 1024" <<< "$dimensions" ||
     ! grep -Fq "pixelHeight: 1024" <<< "$dimensions"; then
    echo "App icon source must be a 1024x1024 image: $ICON_SOURCE" >&2
    exit 1
  fi

  rm -rf "$ICONSET_DIR" "$ICON_PATH"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png"
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png"
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png"
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png"
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png"
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png"
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png"
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png"
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png"
  cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"

  iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"
  cp "$ICON_PATH" "$RESOURCES_DIR/MotionSpec.icns"
}

create_dmg() {
  rm -rf "$DMG_STAGING_DIR"
  mkdir -p "$DMG_STAGING_DIR" "$RELEASE_DIR"

  cp -R "$APP_DIR" "$DMG_STAGING_DIR/$APP_NAME.app"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"

  rm -f "$DMG_PATH"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
}

load_local_config

cd "$ROOT_DIR"
swift build -c release --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>MotionSpec</string>
  <key>CFBundleIdentifier</key>
  <string>com.motionspec.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>MotionSpec.icns</string>
  <key>CFBundleName</key>
  <string>MotionSpec</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

create_app_icon

sign_app

create_dmg

echo "Built $APP_DIR"
echo "Built $DMG_PATH"
