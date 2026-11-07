#!/bin/bash
# Release paketi denetimi (27.10.2026: bulut 1.0'da AÇIK — kullanıcının kendi Drive/S3 hesabı, Shotmori sunucusu yok).
# Kullanım: scripts/check-release-binary.sh <Shotmori.app>
# Denetimler:
#  - bulut metin tablosu pakette (tr/en Cloud.strings) ve bulut türleri ikilide (eksik derleme bayrağı yakalanır),
#  - entitlement'larda app-sandbox + network.client + network.server (OAuth loopback dinleyicisi) var; başka ağ/izin anahtarı yok,
#  - ikilide sistem kısayol tercihi metni (`symbolichotkeys`) yok (Release okumaz),
#  - otomasyon yüzeyleri (27.10.2026): Info.plist'te CFBundleURLTypes/NSServices/CFBundleDocumentTypes, App Intents meta verisi,
#    ServicesMenu/AppShortcuts metinleri; gömülü ShotmoriWidgets.appex imzalı, sandbox'lı, yalnız App Group izniyle.
#  - lisans bildirimi (30.10.2026): Resources/ThirdPartyNotices.txt pakette ve "MIT License" içerir.
# Bir ihlal → çıkış kodu 1.
set -uo pipefail
APP="${1:-}"
[ -n "$APP" ] && [ -d "$APP" ] || { echo "Kullanım: $0 <Shotmori.app>" >&2; exit 2; }
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist" 2>/dev/null || echo Shotmori)"
[ -f "$BIN" ] || { echo "İkili bulunamadı: $BIN" >&2; exit 2; }
fail=0
bad() { echo "İHLAL: $*" >&2; fail=1; }
str=$(strings -a "$BIN")
grep -qF -- "symbolichotkeys" <<<"$str" && bad "ikilide sistem kısayol tercihi metni: symbolichotkeys"
# Bulut gerçekten paketlendi mi: uç noktalar + tür adları (yansıma meta verisi)
# Kısa literal'ler (≤15 bayt) Swift'te satır içi saklanır, strings'te görünmez; uzun olanlar seçildi.
for p in https://www.googleapis.com/drive/v3 https://oauth2.googleapis.com/token AWS4-HMAC-SHA256 x-amz-content-sha256; do grep -qF -- "$p" <<<"$str" || bad "ikilide bulut uç noktası yok: $p (SHOTMORI_CLOUD Release'te tanımlı mı?)"; done
for t in GoogleOAuth S3Signer LoopbackServer UploadQueue; do grep -qF -- "$t" <<<"$str" || bad "ikilide bulut türü yok: $t"; done
for lang in tr en; do [ -f "$APP/Contents/Resources/$lang.lproj/Cloud.strings" ] || bad "pakette $lang.lproj/Cloud.strings yok (EXCLUDED_SOURCE_FILE_NAMES?)"; done
# Otomasyon yüzeyleri: dış giriş yollarının bildirimleri, App Intents meta verisi ve metin tabloları
for k in CFBundleURLTypes NSServices CFBundleDocumentTypes; do
  /usr/libexec/PlistBuddy -c "Print :$k" "$APP/Contents/Info.plist" >/dev/null 2>&1 || bad "Info.plist'te $k yok"
done
[ -d "$APP/Contents/Resources/Metadata.appintents" ] || bad "pakette Metadata.appintents yok (App Intents meta verisi çıkarılmadı)"
for lang in tr en; do for t in ServicesMenu AppShortcuts; do
  [ -f "$APP/Contents/Resources/$lang.lproj/$t.strings" ] || bad "pakette $lang.lproj/$t.strings yok"
done; done
# Lisans bildirimi (30.10.2026): MIT metni pakette olmalı (Tendedero/ClipBoardLine uyarlaması)
NOTICE="$APP/Contents/Resources/ThirdPartyNotices.txt"
if [ -f "$NOTICE" ]; then grep -qF "MIT License" "$NOTICE" || bad "ThirdPartyNotices.txt içinde 'MIT License' yok"; else bad "pakette Contents/Resources/ThirdPartyNotices.txt yok"; fi
APPEX="$APP/Contents/PlugIns/ShotmoriWidgets.appex"
if [ -d "$APPEX" ]; then
  codesign -v --strict "$APPEX" 2>/dev/null || bad "ShotmoriWidgets.appex imzası geçersiz"
  if xents=$(codesign -d --entitlements - "$APPEX" 2>/dev/null) && [ -n "$xents" ]; then
    grep -qF "com.apple.security.app-sandbox" <<<"$xents" || bad "widget entitlement'larında app-sandbox yok"
    grep -qF "ANW6K6228Y.dev.shotmori" <<<"$xents" || bad "widget entitlement'larında App Group (ANW6K6228Y.dev.shotmori) yok"
    xextra=$(grep -oE 'com\.apple\.security\.[a-z.-]+' <<<"$xents" | sort -u | grep -vE '^com\.apple\.security\.(app-sandbox|application-groups|get-task-allow)$' || true)
    [ -n "$xextra" ] && bad "widget'ta beklenmeyen entitlement: $(tr '\n' ' ' <<<"$xextra")"
  else
    bad "ShotmoriWidgets.appex imzasız ya da entitlement'sız"
  fi
else
  bad "pakette Contents/PlugIns/ShotmoriWidgets.appex yok"
fi
if ents=$(codesign -d --entitlements - "$APP" 2>/dev/null); then
  grep -qF "com.apple.security.app-sandbox" <<<"$ents" || bad "entitlement'larda app-sandbox yok"
  grep -qF "com.apple.security.network.client" <<<"$ents" || bad "entitlement'larda network.client yok (Drive/S3 istekleri)"
  grep -qF "com.apple.security.network.server" <<<"$ents" || bad "entitlement'larda network.server yok (OAuth loopback)"
  grep -qF "ANW6K6228Y.dev.shotmori" <<<"$ents" || bad "entitlement'larda App Group (ANW6K6228Y.dev.shotmori) yok (widget anlık görüntüsü)"
  # Beklenmeyen izin anahtarı: yalnız sandbox, kullanıcı seçimli dosya, bookmark, iki ağ izni ve App Group (get-task-allow yerel geliştirme imzasından gelir; dağıtım betikleri ayrıca reddeder)
  extra=$(grep -oE 'com\.apple\.security\.[a-z.-]+' <<<"$ents" | sort -u | grep -vE '^com\.apple\.security\.(app-sandbox|files\.user-selected\.read-write|files\.bookmarks\.app-scope|network\.client|network\.server|application-groups|get-task-allow)$' || true)
  [ -n "$extra" ] && bad "beklenmeyen entitlement: $(tr '\n' ' ' <<<"$extra")"
else
  echo "Not: paket imzasız; entitlement denetimi atlandı."
fi
if [ $fail = 0 ]; then echo "PASS: Release paketinde bulut ve otomasyon yüzeyleri eksiksiz, izinler beklendiği gibi ($APP)"; else echo "FAIL: Release paketi denetimi ($APP)" >&2; fi
exit $fail
