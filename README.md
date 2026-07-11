# MotionSpec

MotionSpec is a native macOS utility for turning short UI animations into LLM-ready frame sets and builder-focused motion descriptions.

MotionSpec captures a short screen, window, or region recording, extracts useful PNG frames, and builds a prompt that helps an LLM understand the movement, timing, easing, and UI state changes.

## Install From This Repository

Requirements: macOS 14 or newer.

```bash
git clone <your-motion-spec-repo-url>
cd motionspec
open release/MotionSpec.dmg
```

In the mounted disk image, drag `MotionSpec.app` into `Applications`, then launch it from Applications.

The first capture requires macOS Screen Recording permission. If macOS blocks launch because the app is not notarized yet, right-click `MotionSpec.app`, choose Open, and confirm.

## What Works

- Native SwiftUI app shell with a main window and menu bar controls.
- Capture modes for region, window, and screen.
- ScreenCaptureKit recording with AVFoundation frame extraction.
- Smart keyframes, even interval frames, and manual frame selection.
- Clipboard copy for selected frames plus a motion-spec prompt.
- Folder export for PNG frames and prompt text.
- Gemini BYOK, Codex CLI, and custom CLI description paths.
- Ephemeral session storage by default.

## Build From Source

Requirements:

- macOS 14 or newer
- Xcode / Swift toolchain

Run directly during development:

```bash
swift run MotionSpec
```

Build the local app bundle and DMG:

```bash
bash scripts/package_app.sh
```

Outputs:

- `dist/MotionSpec.app`
- `release/MotionSpec.dmg`

The `release/MotionSpec.dmg` file is intended to be committed so people can clone the repo, open the DMG, drag the app to Applications, and start using it.

## Test

```bash
swift test
```

## Local Signing

The package script signs `dist/MotionSpec.app` before creating the DMG when a signing identity is configured.

For stable macOS Screen Recording permissions between rebuilds, sign the app with the same local signing identity each time. Ad-hoc signing is only a fallback and can still make macOS ask again after rebuilds.

The easiest local setup is:

```bash
bash scripts/setup_local_signing.sh
```

That creates a self-signed local code-signing identity named `MotionSpec Local Development` in your login keychain and writes `.motionspec-package.env` so future packaging uses it automatically.

If you already have an Apple Development identity, you can use that instead. First find a code-signing identity:

```bash
security find-identity -v -p codesigning
```

Then create a local packaging config:

```bash
echo 'CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"' > .motionspec-package.env
```

After that, `bash scripts/package_app.sh` will sign every rebuild automatically. If you do not have any signing identity yet and only need a quick local build, you can ad-hoc sign for testing, but macOS privacy permissions may not persist:

```bash
echo 'MOTIONSPEC_ADHOC_SIGN=1' > .motionspec-package.env
```

Apple Development or Developer ID signing is the better option for keeping privacy permissions stable. Notarization is still the distribution step to add before sharing broadly.

## Privacy

MotionSpec stores capture sessions ephemerally by default. Frames and recordings are kept in temporary storage and cleaned up unless explicitly exported.

AI description is explicit and user-triggered. Local frame extraction works without any AI provider configured.

## License

MotionSpec is released under the MIT License. See [LICENSE](LICENSE).
