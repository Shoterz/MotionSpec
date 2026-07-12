#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package_app.sh"
SETUP_SCRIPT="$ROOT_DIR/scripts/setup_local_signing.sh"

bash -n "$PACKAGE_SCRIPT"
bash -n "$SETUP_SCRIPT"

require_text() {
  local text="$1"
  local description="$2"

  if ! grep -Fq "$text" "$PACKAGE_SCRIPT"; then
    echo "Missing $description in package_app.sh" >&2
    exit 1
  fi
}

require_text ".motionspec-package.env" "local signing config support"
require_text "CODESIGN_IDENTITY" "codesign identity support"
require_text "MOTIONSPEC_ADHOC_SIGN" "ad-hoc signing switch"
require_text "codesign --force --deep" "codesign invocation"
require_text "release/MotionSpec.dmg" "tracked DMG output path"
require_text "hdiutil create" "DMG creation"
require_text "Applications" "Applications shortcut in DMG"
require_text "setup_local_signing.sh" "stable local signing setup guidance"
require_text "Skipping codesign" "unsigned-build guidance"
require_text 'ICON_SOURCE="$ROOT_DIR/logo.png"' "source icon path"
require_text "pixelWidth: 1024" "source icon width validation"
require_text "pixelHeight: 1024" "source icon height validation"
require_text "sips -z" "icon resizing"
require_text "iconutil -c icns" "icns compilation"
require_text 'cp "$ICON_PATH" "$RESOURCES_DIR/MotionSpec.icns"' "icon bundle copy"
require_text "<key>CFBundleIconFile</key>" "bundle icon declaration"
require_text "<string>MotionSpec.icns</string>" "bundle icon filename"

if ! grep -Fq "MOTIONSPEC_LOCAL_IDENTITY" "$SETUP_SCRIPT"; then
  echo "Missing local signing identity override in setup_local_signing.sh" >&2
  exit 1
fi

if ! grep -Fq "Apple Development" "$SETUP_SCRIPT"; then
  echo "Missing Apple Development identity preference in setup_local_signing.sh" >&2
  exit 1
fi

if ! grep -Fq "openssl req" "$SETUP_SCRIPT"; then
  echo "Missing self-signed certificate generation in setup_local_signing.sh" >&2
  exit 1
fi

if ! grep -Fq "security import" "$SETUP_SCRIPT"; then
  echo "Missing keychain import in setup_local_signing.sh" >&2
  exit 1
fi

if ! grep -Fq "CODESIGN_IDENTITY" "$SETUP_SCRIPT"; then
  echo "Missing package config write in setup_local_signing.sh" >&2
  exit 1
fi
