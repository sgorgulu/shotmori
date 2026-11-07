#!/usr/bin/env bash
# GitHub Release + Homebrew cask akışı (doğrudan indirme kanalı). scripts/release.sh'ın ürettiği notarize edilmiş,
# staple'lanmış Shotmori.app'ten DMG üretir, DMG'yi de notarize edip staple'lar, sha256 alır ve GitHub'da TASLAK sürüm açar.
#
#   scripts/release-github.sh                 # build/release içindeki uygulamadan dmg + zip, taslak GitHub Release (v<sürüm>)
#   scripts/release-github.sh --build         # önce scripts/release.sh'ı çalıştırır
#   scripts/release-github.sh --sync          # herkese açık depoyu (~/Projects/shotmori) dışa aktarıp commit/push eder, sonra sürüm
#   scripts/release-github.sh --publish       # taslağı yayınlar (App Store onayıyla aynı gün) ve Homebrew tap'ini günceller
#
# Gereksinimler: gh (giriş yapılmış), scripts/asc-key.sh (notarytool), Developer ID sertifikası (release.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="sgorgulu/shotmori"; TAP_REPO="sgorgulu/homebrew-tap"; PUBLIC_CLONE="${PUBLIC_CLONE:-$HOME/Projects/shotmori}"
OUT="${OUT_DIR:-build/release}"
BUILD=0; SYNC=0; PUBLISH=0
for a in "$@"; do case "$a" in --build) BUILD=1;; --sync) SYNC=1;; --publish) PUBLISH=1;; *) echo "bilinmeyen seçenek: $a" >&2; exit 2;; esac; done
VERSION=$(grep -E '^\s*MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
TAG="v$VERSION"
APP="$OUT/export/Shotmori.app"; ZIP="$OUT/Shotmori-$VERSION.zip"; DMG="$OUT/Shotmori-$VERSION.dmg"; NOTES="$OUT/notes-$VERSION.md"

[ "$BUILD" = 1 ] && scripts/release.sh
[ -d "$APP" ] || { echo "HATA: $APP yok; önce scripts/release.sh (ya da --build)" >&2; exit 3; }
xcrun stapler validate "$APP" >/dev/null || { echo "HATA: uygulama staple'lanmamış" >&2; exit 4; }
source scripts/asc-key.sh

# --- Herkese açık depo eşitleme (sürüm etiketi bu koda konur) ---------------------------------------------------
if [ "$SYNC" = 1 ]; then
  [ -d "$PUBLIC_CLONE/.git" ] || git clone -q "https://github.com/$REPO.git" "$PUBLIC_CLONE"
  scripts/export-public.sh "$PUBLIC_CLONE"
  ( cd "$PUBLIC_CLONE" && git add -A . && if ! git diff --cached --quiet; then git commit -q -m "Shotmori $VERSION" && git push -q; else echo "herkese açık depo güncel"; fi )
fi

# --- DMG ------------------------------------------------------------------------------------------------------
STAGE="$OUT/dmg-stage"; rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Shotmori.app"; ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Shotmori $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG"
rm -rf "$STAGE"
codesign --force --sign "Developer ID Application" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --key "$KEYFILE" --key-id "$KEYID" --issuer "$ISSUER" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
[ -f "$ZIP" ] || ditto -c -k --keepParent "$APP" "$ZIP"
SHA_DMG=$(shasum -a 256 "$DMG" | cut -d' ' -f1); SHA_ZIP=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
printf '%s  %s\n%s  %s\n' "$SHA_DMG" "$(basename "$DMG")" "$SHA_ZIP" "$(basename "$ZIP")" > "$OUT/SHA256SUMS.txt"

# --- Sürüm notları: sitenin changelog.json'undaki aynı sürüm (EN + TR); yoksa boş şablon -------------------------
SITE_LOG="../shotmori-website/src/changelog.json"
python3 - "$VERSION" "$SITE_LOG" "$NOTES" "$SHA_DMG" "$SHA_ZIP" <<'PY'
import json, sys, os
version, log, out, sha_dmg, sha_zip = sys.argv[1:]
notes = {'en': [], 'tr': []}
if os.path.exists(log):
    d = json.load(open(log))
    for r in d.get('releases', []) + d.get('_taslak', []):
        if r.get('version') and version.startswith(r['version']):
            notes = r['notes']; break
lines = [f'# Shotmori {version}', '', 'Free and open source (MIT). Also on the Mac App Store.', '',
         '**Install:** open the DMG and drag Shotmori to Applications, or `brew install sgorgulu/tap/shotmori`. '
         'Requires macOS 14 Sonoma or later. Signed with Developer ID and notarized by Apple.', '', '## What is in this release', '']
lines += [f'- {n}' for n in notes['en']] or ['- (notes)']
lines += ['', '## Türkçe', ''] + ([f'- {n}' for n in notes['tr']] or ['- (notlar)'])
lines += ['', '## Checksums (SHA-256)', '', '```', f'{sha_dmg}  Shotmori-{version}.dmg', f'{sha_zip}  Shotmori-{version}.zip', '```']
open(out, 'w').write('\n'.join(lines) + '\n')
PY

# --- Homebrew cask ---------------------------------------------------------------------------------------------
CASK="$OUT/shotmori.rb"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__SHA256__/$SHA_DMG/g" packaging/homebrew/shotmori.rb.tmpl > "$CASK"

# --- GitHub Release (taslak) -----------------------------------------------------------------------------------
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" "$ZIP" "$OUT/SHA256SUMS.txt" --repo "$REPO" --clobber
  gh release edit "$TAG" --repo "$REPO" --notes-file "$NOTES"
else
  gh release create "$TAG" "$DMG" "$ZIP" "$OUT/SHA256SUMS.txt" --repo "$REPO" --target main --draft --title "Shotmori $VERSION" --notes-file "$NOTES"
fi
echo "Taslak sürüm: https://github.com/$REPO/releases/tag/$TAG"

# --- Yayın günü: taslağı yayınla, tap'i güncelle ----------------------------------------------------------------
if [ "$PUBLISH" = 1 ]; then
  gh release edit "$TAG" --repo "$REPO" --draft=false --latest
  gh repo view "$TAP_REPO" >/dev/null 2>&1 || gh repo create "$TAP_REPO" --public --description "Homebrew tap for Shotmori" >/dev/null
  TAPDIR=$(mktemp -d); git clone -q "https://github.com/$TAP_REPO.git" "$TAPDIR"
  mkdir -p "$TAPDIR/Casks"; cp "$CASK" "$TAPDIR/Casks/shotmori.rb"
  [ -f "$TAPDIR/README.md" ] || printf '# Shotmori Homebrew tap\n\n```\nbrew install sgorgulu/tap/shotmori\n```\n' > "$TAPDIR/README.md"
  ( cd "$TAPDIR" && git add Casks/shotmori.rb README.md && git commit -q -m "shotmori $VERSION" && git push -q )
  rm -rf "$TAPDIR"
  echo "Yayınlandı: https://github.com/$REPO/releases/tag/$TAG · brew install sgorgulu/tap/shotmori"
else
  echo "Yayınlamak için (App Store onayıyla aynı gün): scripts/release-github.sh --publish"
fi
