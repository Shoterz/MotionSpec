# MotionSpec App Icon and DMG Design

## Goal

Use the supplied `logo.png` unchanged as MotionSpec's macOS application icon, rebuild the distributable disk image, and publish the result to the repository's `main` branch.

## Packaging Design

- Keep `logo.png` as the tracked source artwork.
- Extend `scripts/package_app.sh` to generate a standard macOS `.iconset` from the 1024×1024 source and compile it to `MotionSpec.icns` with `iconutil`.
- Copy `MotionSpec.icns` into `MotionSpec.app/Contents/Resources` and declare it through `CFBundleIconFile` in `Info.plist`.
- Preserve the existing signing behavior and DMG layout.
- Replace the tracked `release/MotionSpec.dmg` with the rebuilt artifact.

## Validation

- Add packaging-script assertions for source icon validation, icon generation, resource copying, and the bundle icon declaration.
- Run the package-script test and the Swift test suite.
- Build the release DMG and inspect its mounted application bundle to confirm the icon resource, `Info.plist` declaration, code-signing state, and expected Applications shortcut.
- Keep unrelated untracked image files out of the commit.

## Publication

Commit only the source logo, packaging/test changes, design documentation, and rebuilt DMG, then push the commit directly to `origin/main` as explicitly requested.
