# Contributing to Shotmori

Thanks for your interest. Shotmori is a small native macOS app (AppKit + SwiftUI, no dependencies). A few things to know before you open an issue or a pull request.

## Reporting a bug

Open a GitHub issue with:

- macOS version and Shotmori version (Settings › About).
- What you did, what you expected, what happened.
- If it helps, the diagnostics log (menu bar icon › Help › Show diagnostics log). The log never contains screenshot content, OCR text or personal paths; still, read it before you paste it.

Please do not attach real screenshots that contain personal data.

## Building

```bash
brew install xcodegen
scripts/bootstrap.sh          # creates the git-ignored CloudSecrets.swift from its example, then runs xcodegen
xcodebuild -scheme Shotmori -configuration Debug build
xcodebuild -scheme Shotmori test
```

Requirements: Xcode 27, macOS 14 or later as the deployment target. The project file is generated from `project.yml`; do not commit `Shotmori.xcodeproj` changes, edit `project.yml` instead.

Debug builds run outside the App Sandbox so you can develop without re-granting folder access. Release builds are sandboxed; `scripts/qa-sandbox.sh` builds a sandboxed copy under a separate bundle identifier so your real data stays untouched.

## Rules that keep the app trustworthy

These are not negotiable in pull requests:

- Shotmori never moves, renames or deletes a user's files on its own. Removing an image from a shelf only removes it from the list. The Trash is reachable only through an explicitly named, confirmed action.
- Edits and resizes write new copies; the original file is never changed.
- No analytics, no account, no server of our own. Network access is used only for the user's own Google Drive or S3-compatible storage, and only when they turn it on.
- Logs never contain screenshot content, OCR text, personal paths, URLs or tokens.
- Every user-facing string lives in `scripts/gen_strings.py` (Turkish and English) and is generated into the `.lproj` folders. Do not edit `Core/Strings.swift` or the `Localizable.strings` files by hand.
- Every feature change updates `docs/ozellikler.md` (the feature catalog, in Turkish) in the same commit.
- Tests and QA scripts must not touch real user data; use `SHOTMORI_DATA_DIR` and `SHOTMORI_DEFAULTS_SUITE` (see `scripts/qa-isolated.sh`).

## Google Drive sign-in in your own build

The App Store build ships with the developer's OAuth client. In your own build, create a "Desktop app" OAuth client in Google Cloud Console (Drive API enabled) and either put its client secret in `Shotmori/Cloud/CloudSecrets.swift` (git-ignored; created by `scripts/bootstrap.sh` from `CloudSecrets.swift.example`) and its ID in `CloudDefaults.swift`, or enter both in Settings › Cloud › Advanced.

## Pull requests

Keep them small and focused. Run the tests. Describe the user-visible change in the PR and update the feature catalog. Turkish and English strings both need to be present.

## License

By contributing you agree that your contributions are licensed under the MIT License in `LICENSE`.
