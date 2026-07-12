# MotionSpec App Icon and DMG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package the supplied 1024×1024 `logo.png` as MotionSpec's macOS app icon and replace the tracked DMG with a verified rebuild.

**Architecture:** The existing Bash packager remains the single release entry point. It validates the source artwork, generates Apple's standard iconset sizes with `sips`, compiles them with `iconutil`, embeds the resulting `MotionSpec.icns` in the app bundle, and declares the resource in `Info.plist` before the existing signing and DMG steps.

**Tech Stack:** Bash, Swift Package Manager, macOS `sips`, `iconutil`, `codesign`, `hdiutil`, and Git.

## Global Constraints

- Preserve `logo.png` unchanged as the tracked source artwork.
- Preserve the current macOS 14 minimum, signing behavior, application identifier, and DMG layout.
- Publish only the source logo, packaging/test updates, planning documents, and rebuilt `release/MotionSpec.dmg` to `origin/main`.
- Do not stage `demo image.png` or `logo design.png`.

---

### Task 1: Specify and implement icon packaging

**Files:**
- Modify: `scripts/test_package_app_script.sh`
- Modify: `scripts/package_app.sh`
- Add: `logo.png`

**Interfaces:**
- Consumes: `logo.png`, an unchanged 1024×1024 PNG at the repository root.
- Produces: `dist/MotionSpec.app/Contents/Resources/MotionSpec.icns` and an `Info.plist` `CFBundleIconFile` value of `MotionSpec.icns`.

- [ ] **Step 1: Add failing packaging assertions**

Add these assertions to `scripts/test_package_app_script.sh`:

```bash
require_text 'ICON_SOURCE="$ROOT_DIR/logo.png"' "source icon path"
require_text 'sips -z' "icon resizing"
require_text 'iconutil -c icns' "icns compilation"
require_text 'cp "$ICON_PATH" "$RESOURCES_DIR/MotionSpec.icns"' "icon bundle copy"
require_text '<key>CFBundleIconFile</key>' "bundle icon declaration"
require_text '<string>MotionSpec.icns</string>' "bundle icon filename"
```

- [ ] **Step 2: Run the packaging test and verify the new assertion fails**

Run: `bash scripts/test_package_app_script.sh`

Expected: nonzero exit with `Missing source icon path in package_app.sh`.

- [ ] **Step 3: Add icon generation and embedding**

In `scripts/package_app.sh`, define `RESOURCES_DIR`, `ICON_SOURCE`, `ICONSET_DIR`, and `ICON_PATH`. Add a `create_app_icon` function that:

```bash
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
```

Create `Contents/Resources`, call `create_app_icon` before signing, and add the following dictionary entry to the generated `Info.plist`:

```xml
<key>CFBundleIconFile</key>
<string>MotionSpec.icns</string>
```

- [ ] **Step 4: Run focused validation**

Run: `bash scripts/test_package_app_script.sh`

Expected: exit 0 with no missing assertion output.

Run: `bash -n scripts/package_app.sh scripts/test_package_app_script.sh`

Expected: exit 0 with no syntax errors.

### Task 2: Rebuild and inspect the distributable

**Files:**
- Modify: `release/MotionSpec.dmg`

**Interfaces:**
- Consumes: the updated packager and source icon from Task 1.
- Produces: a mountable DMG containing `MotionSpec.app`, its declared icon, and the Applications shortcut.

- [ ] **Step 1: Run the full source test suite**

Run: `swift test`

Expected: exit 0 and zero failed tests.

- [ ] **Step 2: Build the release artifact**

Run: `bash scripts/package_app.sh`

Expected: exit 0 with `Built .../dist/MotionSpec.app` and `Built .../release/MotionSpec.dmg`.

- [ ] **Step 3: Verify the app bundle and signature**

Run:

```bash
test -f dist/MotionSpec.app/Contents/Resources/MotionSpec.icns
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' dist/MotionSpec.app/Contents/Info.plist)" = "MotionSpec.icns"
codesign --verify --deep --strict dist/MotionSpec.app
```

Expected: all commands exit 0.

- [ ] **Step 4: Mount and inspect the DMG**

Attach `release/MotionSpec.dmg` with `hdiutil attach -readonly -nobrowse -plist`, inspect the reported mount point, and verify:

```bash
test -d "$MOUNT_POINT/MotionSpec.app"
test -L "$MOUNT_POINT/Applications"
test -f "$MOUNT_POINT/MotionSpec.app/Contents/Resources/MotionSpec.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$MOUNT_POINT/MotionSpec.app/Contents/Info.plist")" = "MotionSpec.icns"
codesign --verify --deep --strict "$MOUNT_POINT/MotionSpec.app"
```

Expected: all commands exit 0. Detach the volume afterward with `hdiutil detach "$MOUNT_POINT"`.

### Task 3: Publish the verified update

**Files:**
- Add: `docs/superpowers/plans/2026-07-12-app-icon-dmg.md`
- Add: `logo.png`
- Modify: `scripts/package_app.sh`
- Modify: `scripts/test_package_app_script.sh`
- Modify: `release/MotionSpec.dmg`

**Interfaces:**
- Consumes: the verified working tree and explicit authorization to update `main`.
- Produces: a pushed `origin/main` commit containing the new app icon and DMG.

- [ ] **Step 1: Audit the exact publication diff**

Run:

```bash
git diff --check
git status --short
git diff -- scripts/package_app.sh scripts/test_package_app_script.sh
```

Expected: no whitespace errors; only the intended tracked files plus the two explicitly excluded loose images appear.

- [ ] **Step 2: Stage only intended files and commit**

Run:

```bash
git add logo.png scripts/package_app.sh scripts/test_package_app_script.sh release/MotionSpec.dmg docs/superpowers/plans/2026-07-12-app-icon-dmg.md
git commit -m "Package MotionSpec with app icon"
```

Expected: a new commit on `main`; neither `demo image.png` nor `logo design.png` is staged.

- [ ] **Step 3: Push the main branch**

Run: `git push origin main`

Expected: exit 0 and remote `main` advances to the new commit.

- [ ] **Step 4: Verify remote publication**

Run: `git ls-remote origin refs/heads/main`

Expected: the remote hash matches `git rev-parse HEAD`.
