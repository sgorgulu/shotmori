#!/bin/bash
# Mac App Store paketi: arşiv → .pkg (bulut imzalama: Apple Distribution + Mac Installer, ASC API anahtarıyla) → denetim → [yükleme].
# Varsayılan yalnız paketi hazırlar ve denetler. Yüklemek için: ASC_APP_ID=… scripts/release-mas.sh --upload
# Gereksinimler: scripts/asc-key.sh'deki Admin API anahtarı; --upload için `asc auth login` ve ASC_APP_ID.
# Sürüm: project.yml MARKETING_VERSION; build numarası BUILD_NUMBER ile ezilebilir (her yüklemede artmalı).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/asc-key.sh
UPLOAD=0; [ "${1:-}" = "--upload" ] && UPLOAD=1
OUT="${OUT_DIR:-build/release-mas}"; rm -rf "$OUT"; mkdir -p "$OUT"
VERSION=$(grep -E '^\s*MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
BUILD="${BUILD_NUMBER:-$(grep -E '^\s*CURRENT_PROJECT_VERSION' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')}"
if [ $UPLOAD = 1 ]; then
  [ -n "${ASC_APP_ID:-}" ] || { echo "EKSİK: ASC_APP_ID (App Store Connect uygulama kimliği). Bulmak için: asc apps list --output table" >&2; exit 5; }
fi

xcodegen generate >/dev/null
xcodebuild -project Shotmori.xcodeproj -scheme Shotmori -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$OUT/Shotmori.xcarchive" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=ANW6K6228Y \
  CURRENT_PROJECT_VERSION="$BUILD" "${AUTH[@]}" archive > "$OUT/archive.log" 2>&1 || { tail -25 "$OUT/archive.log"; exit 7; }
xcodebuild -exportArchive -archivePath "$OUT/Shotmori.xcarchive" -exportOptionsPlist scripts/ExportOptions-AppStore.plist \
  -exportPath "$OUT/export" "${AUTH[@]}" > "$OUT/export.log" 2>&1 || { tail -25 "$OUT/export.log"; exit 8; }
PKG=$(ls "$OUT/export"/*.pkg | head -1)

# Denetim (paketin içindeki imzalı uygulama): sandbox var; get-task-allow yok; gizlilik beyanı ve doğru sürüm;
# bulut eksiksiz + ağ izinleri (check-release-binary.sh; 27.10.2026'dan beri bulut 1.0'da açık).
pkgutil --expand-full "$PKG" "$OUT/pkg-expanded" >/dev/null
APP=$(find "$OUT/pkg-expanded" -name Shotmori.app -maxdepth 4 | head -1)
ents=$(codesign -d --entitlements - "$APP" 2>/dev/null)
grep -q "com.apple.security.app-sandbox" <<<"$ents" || { echo "HATA: app-sandbox yok" >&2; exit 10; }
if grep -q "get-task-allow" <<<"$ents"; then echo "HATA: get-task-allow var (geliştirme imzası)" >&2; exit 11; fi
[ -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" ] || { echo "HATA: PrivacyInfo.xcprivacy pakette yok" >&2; exit 13; }
{ [ -d "$APP/Contents/PlugIns/ShotmoriWidgets.appex" ] && codesign -v --strict "$APP/Contents/PlugIns/ShotmoriWidgets.appex"; } || { echo "HATA: PlugIns/ShotmoriWidgets.appex yok ya da imzasız" >&2; exit 15; }
scripts/check-release-binary.sh "$APP" || { echo "HATA: Release paketi denetimi (bulut/izinler)" >&2; exit 14; }
codesign -dvv "$APP" 2>&1 | grep -E '^Authority=' | head -1
pkgutil --check-signature "$PKG" | sed -n 2,3p
echo "Paket hazır: $PKG (sürüm $VERSION, build $BUILD)"

if [ $UPLOAD = 1 ]; then
  asc builds upload --app "$ASC_APP_ID" --pkg "$PKG" --version "$VERSION" --build-number "$BUILD" --wait
else
  echo "Yüklenmedi. Yüklemek için: ASC_APP_ID=… BUILD_NUMBER=$BUILD scripts/release-mas.sh --upload"
fi
