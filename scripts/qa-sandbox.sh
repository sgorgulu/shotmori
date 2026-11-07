#!/bin/zsh
# Sandbox QA: Release derlemesi AYRI kimlikle (dev.shotmori.sandboxqa) → ayrı konteyner, gerçek veriye dokunmaz.
# container-migration.plist paketten silinir: aksi hâlde ilk açılışta kullanıcının gerçek
# ~/Library/Application Support/Shotmori klasörü QA konteynerine TAŞINIR.
# Kullanım: scripts/qa-sandbox.sh build | launch | kill | entitlements | log | reset
set -e
cd "$(dirname "$0")/.."
QA_ID=dev.shotmori.sandboxqa
DD="${QA_DERIVED_DATA:-${TMPDIR%/}/shotmori-sandboxqa-dd}"
APP="$DD/Build/Products/Release/Shotmori.app"
CONTAINER="$HOME/Library/Containers/$QA_ID"
case "$1" in
  build)
    xcodebuild -scheme Shotmori -configuration Release -destination 'platform=macOS' -derivedDataPath "$DD" \
      PRODUCT_BUNDLE_IDENTIFIER="$QA_ID" build > "$DD.build.log" 2>&1 || { tail -20 "$DD.build.log"; exit 1; }
    rm -f "$APP/Contents/Resources/container-migration.plist"
    identity=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Apple Development.*\)$/\1/p' | head -1)
    [ -n "$identity" ] || { echo "HATA: paket Apple Development ile imzalanmamış; anahtar zincirinde 'Apple Development' sertifikası gerekli (security find-identity -v -p codesigning)"; exit 1; }
    codesign --force --sign "$identity" --options runtime --entitlements Shotmori/Shotmori.entitlements "$APP"
    [ -f "$APP/Contents/Resources/container-migration.plist" ] && { echo "HATA: göç dosyası pakette"; exit 1; }
    echo "derlendi: $APP ($QA_ID, göç dosyası yok)" ;;
  launch)
    pgrep -f "$APP/Contents/MacOS/Shotmori" >/dev/null && { echo "zaten çalışıyor"; exit 0; }
    open -n "$APP"; sleep 3
    echo "pid: $(pgrep -f "$APP/Contents/MacOS/Shotmori" || echo yok)" ;;
  kill) pkill -f "$APP/Contents/MacOS/Shotmori" 2>/dev/null || true; echo "kapatıldı" ;;
  entitlements) codesign -d --entitlements - "$APP" 2>/dev/null | grep -oE 'com\.apple\.security\.[a-z.-]+' ;;
  log) tail -n "${2:-20}" "$CONTAINER/Data/Library/Logs/Shotmori.log" ;;
  reset) # QA konteynerinin verisini sil (yalnız QA kimliği; gerçek dev.shotmori.app'e dokunmaz)
    pkill -f "$APP/Contents/MacOS/Shotmori" 2>/dev/null || true
    rm -rf "$CONTAINER/Data/Library/Application Support/Shotmori" "$CONTAINER/Data/Library/Logs/Shotmori.log"
    defaults delete "$QA_ID" 2>/dev/null || true; echo "QA konteyner verisi silindi" ;;
  *) echo "kullanım: $0 build|launch|kill|entitlements|log|reset"; exit 2 ;;
esac
