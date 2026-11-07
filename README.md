# Shotmori

**The screenshot shelf for Mac.** Free and open source (MIT).

Keep taking screenshots with the macOS shortcuts you already use. Shotmori collects the files macOS saves onto a shelf, so you can pick a few, crop or redact them, and drag them straight into the next app, including Claude, ChatGPT, Codex, Jira, Slack or Keynote, without opening Finder.

Website and guides: https://shotmori.com · Turkish: https://shotmori.com/tr/

## What it does

- **Collects** new screenshots from the folder you choose. It does not take screenshots itself and never asks for Screen Recording permission.
- **Two shelf styles:** a floating panel that opens beside your pointer without stealing focus, or a top strip that comes down from the top of the screen with your screenshots pinned to a line.
- **Up to 8 named shelves**, switch with ⌘1–⌘8, move images between shelves, open a shelf in its own window.
- **Prepare:** crop (free, square, 16:9), cover details with solid redaction, resize to PNG or JPEG with an estimated file size, copy text with on-device recognition. Edits always create a new copy.
- **Transfer:** drag one or several images as real files into any app that accepts files. Copy, share, open with, save a copy.
- **Your own cloud, optional:** upload to your Google Drive or an S3-compatible bucket, copy a link (plain URL, Markdown or HTML), or back up new screenshots automatically. Shotmori has no server of its own; credentials stay in the macOS Keychain.
- **Automation:** Shortcuts actions, Control Center buttons (macOS 26+), a Recent Images widget, a Finder service, Open With, drop on the menu bar icon, `shotmori://` links.
- English and Turkish interface. macOS 14 Sonoma or later.

What it does not do, on purpose: no blur or pixelation (redaction is a solid box), no arrows or text annotation, no screen recording or GIFs, no OCR of your screen (only of images on the shelf), no Dropbox/iCloud/OneDrive/Imgur, no AI analysis (an AI app receives the file).

## Install

- **Mac App Store:** free, no in-app purchases. Link on https://shotmori.com/download/ when the release is live.
- **GitHub Releases:** notarized `.dmg` for the same version, once Developer ID signing is set up.
- **Build it yourself:** see below.

## Build

```bash
brew install xcodegen
git clone https://github.com/sgorgulu/shotmori.git
cd shotmori
scripts/bootstrap.sh
xcodebuild -scheme Shotmori -configuration Debug build
```

Xcode 27 is required. `xcodebuild -scheme Shotmori test` runs the unit tests. Debug builds run outside the App Sandbox; Release builds are sandboxed. Google Drive sign-in in your own build needs your own OAuth client, see `CONTRIBUTING.md`.

## Privacy

Shotmori collects no data and has no analytics or account. It reads only the folder you select (security-scoped bookmark) and connects to the network only for the cloud account you add. Full policy: https://shotmori.com/privacy/

## Project layout

- `Shotmori/` app sources: `Core` (shelf store, folder watcher, file inspector, text recognition), `Panel` (floating shelf, editor, resize), `Strip` (top strip), `MenuBar`, `Settings`, `Cloud` (Drive, S3, upload queue), `Intents` (Shortcuts), `Onboarding`, `UI` (glass surfaces, style).
- `ShotmoriWidgets/` the Recent Images widget and Control Center controls. `Shared/` snapshot model shared with the widget.
- `ShotmoriTests/` unit tests.
- `docs/ozellikler.md` the feature catalog (Turkish): every user-visible feature, how it works, where it lives.
- `scripts/` string generation, QA, release.

## Credits

The top strip, card motion and capture flight are adapted from [Tendedero](https://github.com/alejandrobujan/tendedero) (Alejandro Buján) and ClipBoardLine, both MIT. See `THIRD_PARTY_NOTICES.md`.

## License

MIT, see `LICENSE`. The name "Shotmori" and the app icon are not part of the license.
