#!/bin/zsh
# Yalıtılmış QA ortamı: sahte HOME (raf, günlük), sentetik ekran görüntüleri, argüman tabanlı tercihler (gerçek plist'e yazılmaz).
# Widget: SHOTMORI_DATA_DIR verilince anlık görüntü gerçek App Group konteyneri yerine "$HOME_Q/Library/WidgetGroup"a yazılır;
# gerçek widget bunu görmez (widget/Denetim Merkezi provası sahip örneğinde). URL/open -b/Servis istekleri Launch Services'in
# seçtiği dev.shotmori.app'e gider: /Applications/Shotmori.app çalışıyorsa yalıtılmış örneğe değil ona düşer.
set -e
# Çalışma dizini ve uygulama yolu ortamdan gelir; verilmezse geçici dizin ve en son Debug derlemesi (DerivedData).
SP="${SHOTMORI_QA_DIR:-${TMPDIR:-/tmp}/shotmori-qa}"
Q="$SP/qa"; HOME_Q="$Q/home"; SHOTS="$Q/shots"; OUT="$Q/out"
APP="${SHOTMORI_APP:-$(ls -td ~/Library/Developer/Xcode/DerivedData/Shotmori-*/Build/Products/Debug/Shotmori.app 2>/dev/null | head -1)}"
case "$1" in
  setup)
    rm -rf "${HOME_Q:?}" "${SHOTS:?}"; mkdir -p "$HOME_Q/Library/Application Support/Shotmori" "$HOME_Q/Library/Logs" "$SHOTS" "$OUT"
    if [ "$2" = empty ]; then printf '{"items":[],"lastHandoffAt":null}\n' > "$HOME_Q/Library/Application Support/Shotmori/shelf.json"; echo "boş raf"; exit 0; fi
    [ -x "$Q/mkshot" ] || swiftc -O -o "$Q/mkshot" "$Q/mkshot.swift" 2>&1 | grep -v warning || true
    i=0; items=""
    while IFS='|' read -r name w h title theme; do
      i=$((i+1)); f="$SHOTS/$name"; "$Q/mkshot" "$f" "$w" "$h" "$title" "$theme" >/dev/null
      # mtime dün: gerçek lastSeenCaptureDate'ten eski → catchUp tetiklenmez, tercih yazılmaz
      touch -t "$(date -v-1d +%Y%m%d)11$(printf '%02d' $((50-i*2)))" "$f"
      cap="$(date -u -v-1d +%Y-%m-%d)T08:$(printf '%02d' $((50-i*2))):00Z"
      items="$items{\"id\":\"$(uuidgen)\",\"path\":\"$f\",\"capturedAt\":\"$cap\",\"addedAt\":\"$cap\",\"source\":\"screenshot\",\"startsGroup\":false},"
    done <<'LIST'
Proje notları ve toplantı özeti 2026-10-18 11.48.png|1600|1000|Bir sonraki adım|light
Görsel düzenleme taslağı 11.46.png|1200|800|Sade bir başlangıç.|light
Örnek kod 11.44.png|1400|900|struct Demo|code
Haftalık görünüm 11.42.png|1600|900|Haftalık görünüm|chart
Notlar 11.40.png|900|1200|Notlar|light
Koyu arayüz 11.38.png|1800|1000|Ayarlar|dark
LIST
    # 2 yeni (ilk iki öğe), kalan 4 aktarılmış: lastHandoffAt 2. ile 3. arasında
    hand="$(date -u -v-1d +%Y-%m-%d)T08:45:00Z"
    printf '{"items":[%s],"lastHandoffAt":"%s"}\n' "${items%,}" "$hand" > "$HOME_Q/Library/Application Support/Shotmori/shelf.json"
    python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print('shelf.json:',len(d['items']),'öğe, handoff',d['lastHandoffAt'])" "$HOME_Q/Library/Application Support/Shotmori/shelf.json"
    ls "$SHOTS" | wc -l | tr -d ' ' ;;
  launch)  # launch light|dark [extra args]
    mode="$2"; shift 2
    extra=(); if [ "$mode" = dark ]; then export SHOTMORI_APPEARANCE=dark; else export SHOTMORI_APPEARANCE=light; fi
    # Tercihler ayrı QA domain'inde (gerçek dev.shotmori.app plist'ine yazılmaz); veri yolları SHOTMORI_DATA_DIR altında.
    defaults write dev.shotmori.qa customFolderPath -string "$SHOTS"; defaults write dev.shotmori.qa onboardingDone -bool "${QA_ONBOARDING_DONE:-YES}"; defaults write dev.shotmori.qa uiLanguage -string tr
    defaults write dev.shotmori.qa hotKeyCode -int 3; defaults write dev.shotmori.qa hotKeyModifiers -int 1835008
    SHOTMORI_DATA_DIR="$HOME_Q/Library" SHOTMORI_DEFAULTS_SUITE=dev.shotmori.qa "$APP/Contents/MacOS/Shotmori" -AppleLanguages '(tr)' "${extra[@]}" "$@" > "$OUT/stdout-$mode.txt" 2>&1 &
    echo $! > "$Q/pid"; sleep 3; echo "pid $(cat $Q/pid) çalışıyor: $(ps -p $(cat $Q/pid) -o comm= | wc -l | tr -d ' ')" ;;
  kill)
    if [ -f "$Q/pid" ]; then kill "$(cat "$Q/pid")" 2>/dev/null || true; rm -f "$Q/pid"; fi; sleep 0.5; echo "QA örneği kapatıldı; kalan Shotmori süreçleri: $(pgrep -x Shotmori | wc -l | tr -d ' ')" ;;
  cleanup) defaults delete dev.shotmori.qa 2>/dev/null || true; echo "QA tercih domain'i silindi" ;;
  win)  # Shotmori pencereleri (her iki örnek), yalnız ekranda olanlar
    "$SP/statusitem" | grep 'onscreen=1' || true ;;
  log) tail -5 "$HOME_Q/Library/Logs/Shotmori.log" ;;
esac
