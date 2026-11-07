#!/bin/bash
# Shotmori doğrudan indirme paketi (shotmori.com): arşiv → Developer ID ile dışa aktar → denetim → notarize → staple → zip.
# App Store sürümüyle aynı sandbox'lı Release derlemesidir (aynı entitlement'lar, bulut açık: kullanıcının kendi hesabı); yalnız imza farklı.
# App Store paketi için: scripts/release-mas.sh
# İmza ve notarization ASC API anahtarıyla (scripts/asc-key.sh, Admin): Developer ID sertifikası bulutta yönetilir,
# notarytool aynı anahtarla gönderir — yerel sertifika ve notarytool profili gerekmez.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/asc-key.sh
OUT="${OUT_DIR:-build/release}"; rm -rf "$OUT"; mkdir -p "$OUT"
VERSION=$(grep -E '^\s*MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')


xcodegen generate >/dev/null
xcodebuild -project Shotmori.xcodeproj -scheme Shotmori -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$OUT/Shotmori.xcarchive" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=ANW6K6228Y \
  "${AUTH[@]}" archive > "$OUT/archive.log" 2>&1 || { tail -25 "$OUT/archive.log"; exit 7; }
xcodebuild -exportArchive -archivePath "$OUT/Shotmori.xcarchive" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$OUT/export" "${AUTH[@]}" > "$OUT/export.log" 2>&1 || {
    if grep -q "cloud-managed distribution certificates\|No signing certificate \"Developer ID Application\"" "$OUT/export.log"; then
      echo "EKSİK: Developer ID imzası. Hesap Sahibi ya (a) bu Mac'te Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application" >&2
      echo "       ile sertifikayı oluşturmalı, ya da (b) App Store Connect › Users and Access'te bulut yönetimli Developer ID sertifikasına erişim vermeli." >&2
      exit 9
    fi
    tail -25 "$OUT/export.log"; exit 8; }
APP="$OUT/export/Shotmori.app"
ents=$(codesign -d --entitlements - "$APP" 2>/dev/null)
grep -q "com.apple.security.app-sandbox" <<<"$ents" || { echo "HATA: app-sandbox yok" >&2; exit 10; }
if grep -q "get-task-allow" <<<"$ents"; then echo "HATA: get-task-allow var (geliştirme imzası)" >&2; exit 11; fi
[ -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" ] || { echo "HATA: PrivacyInfo.xcprivacy pakette yok" >&2; exit 13; }
{ [ -d "$APP/Contents/PlugIns/ShotmoriWidgets.appex" ] && codesign -v --strict "$APP/Contents/PlugIns/ShotmoriWidgets.appex"; } || { echo "HATA: PlugIns/ShotmoriWidgets.appex yok ya da imzasız" >&2; exit 15; }
scripts/check-release-binary.sh "$APP" || { echo "HATA: Release paketi denetimi (bulut/izinler)" >&2; exit 14; }
ZIP="$OUT/Shotmori-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --key "$KEYFILE" --key-id "$KEYID" --issuer "$ISSUER" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute -vv "$APP"
echo "Hazır: $ZIP"
