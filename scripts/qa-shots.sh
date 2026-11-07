#!/bin/zsh
# Yalıtılmış QA ekran görüntüleri: her yüzey için Debug uygulamasını SHOTMORI_QA_OPEN ile başlatır,
# pencereyi başlığa göre bulup screencapture -l ile yakalar. Gerçek veriye/tercihlere dokunmaz.
# Kullanım: scripts/qa-shots.sh <DerivedData/.../Debug/Shotmori.app> <çıktı dizini> [light|dark] [yüzey…]
# Yüzeyler: settings about shelf-settings actions-settings popover panel editor resize onboarding strip strip-selected
# Dil: QA_LANG=tr (varsayılan) | en; İngilizce görüntüler "-en" son ekiyle yazılır.
set -e
APP="$1"; OUT="$2"; MODE="${3:-light}"; shift 3 2>/dev/null || shift $#
SURFACES=("$@"); [ ${#SURFACES[@]} -eq 0 ] && SURFACES=(settings about shelf-settings actions-settings popover panel editor resize onboarding)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
Q="${TMPDIR:-/tmp}/shotmori-qa"; HOME_Q="$Q/home"; SHOTS="$Q/shots"; mkdir -p "$OUT"
BIN="$APP/Contents/MacOS/Shotmori"; [ -x "$BIN" ] || { echo "uygulama yok: $APP" >&2; exit 2 }
# Örnek veri (bir kez)
if [ ! -f "$HOME_Q/Library/Application Support/Shotmori/shelf.json" ]; then
  rm -rf "$Q"; mkdir -p "$HOME_Q/Library/Application Support/Shotmori" "$HOME_Q/Library/Logs" "$SHOTS"
  swiftc -O -o "$Q/mkshot" "$ROOT/scripts/qa-mkshot.swift" 2>&1 | grep -v warning || true
  i=0; items=""
  while IFS='|' read -r name w h title theme; do
    i=$((i+1)); f="$SHOTS/$name"; "$Q/mkshot" "$f" "$w" "$h" "$title" "$theme" >/dev/null
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
  hand="$(date -u -v-1d +%Y-%m-%d)T08:45:00Z"
  printf '{"items":[%s],"lastHandoffAt":"%s"}\n' "${items%,}" "$hand" > "$HOME_Q/Library/Application Support/Shotmori/shelf.json"
fi
SUITE=dev.shotmori.qa
trap 'defaults delete dev.shotmori.qa shelfStyle 2>/dev/null || true' EXIT
defaults write $SUITE customFolderPath -string "$SHOTS"; defaults write $SUITE onboardingDone -bool YES; defaults write $SUITE uiLanguage -string "${QA_LANG:-tr}"
defaults write $SUITE hotKeyCode -int 3; defaults write $SUITE hotKeyModifiers -int 1835008
# Pencere kimliği: scripts/qa-winid.swift (pid + başlık parçası)
[ -x "$Q/winid" ] || swiftc -O -o "$Q/winid" "$ROOT/scripts/qa-winid.swift" 2>&1 | grep -v warning || true
winid() { "$Q/winid" "$1" "$2"; }
SUF=""; [ "${QA_LANG:-tr}" = en ] && SUF="-en"
for S in "${SURFACES[@]}"; do
  pkill -f "$BIN" 2>/dev/null || true; sleep 0.5
  case "$S" in strip|strip-selected) defaults write $SUITE shelfStyle -string strip;; *) defaults delete $SUITE shelfStyle 2>/dev/null || true;; esac
  onb=YES; PAGE=""; case "$S" in onboarding*) onb=NO; PAGE="${S#onboarding}"; S_OPEN=onboarding;; *) S_OPEN="$S";; esac; defaults write $SUITE onboardingDone -bool $onb
  SHOTMORI_DATA_DIR="$HOME_Q/Library" SHOTMORI_DEFAULTS_SUITE=$SUITE SHOTMORI_APPEARANCE=$MODE SHOTMORI_QA_OPEN=$S_OPEN SHOTMORI_QA_PAGE=$PAGE "$BIN" -AppleLanguages "(${QA_LANG:-tr})" > "$Q/stdout-$S.txt" 2>&1 &
  PID=$!; sleep 2.5
  case $S in settings|about|shelf-settings|actions-settings|cloud-settings) want="ayarları";; editor) want="Düzenle";; resize) want="Boyutlandır";; onboarding*) want="tanıyın";; *) want=any;; esac
  [ "${QA_LANG:-tr}" = en ] && case $S in settings|about|shelf-settings|actions-settings|cloud-settings) want="settings";; editor) want="Edit";; resize) want="Resize";; onboarding*) want="Meet";; esac
  if [ "$S" = strip ] || [ "$S" = strip-selected ]; then
    # Şerit: tam genişlikte başlıksız saydam pano penceresi; pid ile bulunur, yalnız pencere katmanı yakalanır
    # (ekran bölgesi yakalamak arkadaki gerçek pencereleri görüntüye sokar).
    ID=$(winid $PID any)
    if [ -n "$ID" ]; then screencapture -x -o -l "$ID" "$OUT/$S-$MODE$SUF.png" && echo "  ✓ $S-$MODE$SUF ($ID)"; else echo "  ✗ $S-$MODE$SUF (pencere yok)"; fi
  elif [ "$S" = popover ] || [ "$S" = panel ]; then
    # Saydam/cam pencereler: yalnız pencere katmanı yakalanırsa arkadaki materyal boş kalır; ekran bölgesi yakalanır (12 pt pay).
    read -r ID X Y WW HH <<< "$("$Q/winid" $PID "$want" bounds)"
    if [ -n "$ID" ]; then screencapture -x -R "$((X-12)),$((Y-12)),$((WW+24)),$((HH+24))" "$OUT/$S-$MODE$SUF.png" && echo "  ✓ $S-$MODE$SUF (bölge $ID)"; else echo "  ✗ $S-$MODE$SUF (pencere yok)"; fi
  else
    ID=$(winid $PID "$want")
    if [ -n "$ID" ]; then screencapture -x -o -l "$ID" "$OUT/$S-$MODE$SUF.png" && echo "  ✓ $S-$MODE$SUF ($ID)"; else echo "  ✗ $S-$MODE$SUF (pencere yok)"; fi
  fi
  kill $PID 2>/dev/null || true; sleep 0.3
done
defaults delete $SUITE shelfStyle 2>/dev/null || true
pkill -f "$BIN" 2>/dev/null || true
