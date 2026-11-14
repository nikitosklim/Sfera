#!/bin/bash
# загрузить-релиз.sh — загружает на сайт всё, что скачано из GitHub Actions («Сборка релиза»):
# установщики и архивы всех платформ, с правильными именами (с версией), названиями и описаниями.
#
# Использование:
#   ./загрузить-релиз.sh                 берёт файлы из ~/Downloads
#   ./загрузить-релиз.sh ПАПКА           берёт файлы из другой папки
#   ./загрузить-релиз.sh --проверка      ничего не загружает, только показывает, что будет сделано
#   ./загрузить-релиз.sh --заменить      если файл такой версии уже есть на сайте, заменить его
#   ./загрузить-релиз.sh --версия 0.4.5  задать версию вручную (обычно определяется по имени установщика)
#
# Что находит в папке (на любой глубине):
#   • артефакты GitHub Actions: папки или zip с именем sfera-panel-windows, sfera-panel-macos-arm64,
#     sfera-panel-macos-intel, sfera-panel-linux, sfera-panel-android (zip распаковывается во временную папку);
#   • готовые файлы Sfera-Setup-*.exe/.dmg/.deb, Sfera-Panel-*.zip/.tar.xz, Sfera-Panel-Android.apk.
# Токен: переменная SFERA_TOKEN или файл ~/.sfera-token (ключ из /opt/sfera/сайт/admin-token.txt на сервере).
# Адрес сайта: переменная SFERA_SITE (по умолчанию https://языксфера.рф в виде punycode).
set -e

DIR="$HOME/Downloads"; VER=""; DRY=0; REPLACE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --проверка) DRY=1 ;;
    --заменить) REPLACE=1 ;;
    --версия) VER="$2"; shift ;;
    -h|--help) sed -n 2,18p "$0"; exit 0 ;;
    *) DIR="$1" ;;
  esac
  shift
done
[ -d "$DIR" ] || { echo "Нет папки: $DIR"; exit 1; }
SITE="${SFERA_SITE:-https://xn--80ajfm5aev7c8a.xn--p1ai}"; SITE="${SITE%/}"
TOKEN="${SFERA_TOKEN:-$(cat "$HOME/.sfera-token" 2>/dev/null || true)}"
if [ "$DRY" = 0 ] && [ -z "$TOKEN" ]; then
  echo "Нет токена: задайте SFERA_TOKEN или положите его в ~/.sfera-token"; exit 1
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# 1. Распаковываем артефакты GitHub (zip с именем sfera-panel-…).
find "$DIR" -maxdepth 2 -type f -name 'sfera-panel-*.zip' 2>/dev/null | while IFS= read -r ZIP; do
  OUT="$TMP/$(basename "$ZIP" .zip)"; mkdir -p "$OUT"; unzip -q -o "$ZIP" -d "$OUT" || echo "Не удалось распаковать $ZIP"
done
# 2. Собираем нужные файлы: из временной папки и из самой папки (в т. ч. из уже распакованных папок артефактов).
LIST="$TMP/список.txt"; : > "$LIST"
for root in "$TMP" "$DIR"; do
  find "$root" -maxdepth 4 -type f \( -name 'Sfera-Setup-*.exe' -o -name 'Sfera-Setup-*.dmg' -o -name 'Sfera-Setup-*.deb' \
    -o -name 'Sfera-Panel-Windows.zip' -o -name 'Sfera-Panel-macOS.zip' -o -name 'Sfera-Panel-macOS-Intel.zip' \
    -o -name 'Sfera-Panel-Linux.tar.xz' -o -name 'Sfera-Panel-Android.apk' \) 2>/dev/null >> "$LIST"
done
sort -u "$LIST" -o "$LIST"
[ -s "$LIST" ] || { echo "В $DIR не найдено файлов сборки (Sfera-Setup-*, Sfera-Panel-*)."; exit 1; }

# 3. Версия — по имени установщика, если не задана.
if [ -z "$VER" ]; then
  VER=$(sed -nE 's#.*/Sfera-Setup-[A-Za-z-]*-([0-9][0-9.]*[0-9])\.(exe|dmg|deb)$#\1#p' "$LIST" | sort -u | tail -n 1)
fi
[ -n "$VER" ] || { echo "Не удалось определить версию по именам. Задайте: --версия 0.4.4"; exit 1; }
echo "Версия: $VER"; echo "Сайт:   $SITE"; echo

enc() { printf '%s' "$1" | perl -pe 's/([^A-Za-z0-9_.~-])/sprintf("%%%02X",ord($1))/ge'; }
UP="$SITE/%D0%B7%D0%B0%D0%B3%D1%80%D1%83%D0%B7%D0%B8%D1%82%D1%8C"
OK=0; ERRS=0
while IFS= read -r FILE; do
  BASE=$(basename "$FILE")
  case "$BASE" in
    Sfera-Setup-Windows-*.exe)
      NAME="$BASE"; TITLE="Сфера для Windows: установщик"
      DESC="Программа установки панели Сферы для Windows 10 и 11 (64-бит). Создаёт ярлыки и запись в «Приложениях», права администратора не нужны. После установки откройте «Панель Сферы» и нажмите «Установить Сферу»." ;;
    Sfera-Setup-macOS-Intel-*.dmg)
      NAME="$BASE"; TITLE="Сфера для macOS: Intel"
      DESC="Образ диска для Mac с процессором Intel. Откройте и перетащите «Панель Сферы» в «Программы». При первом запуске нажмите правой кнопкой → «Открыть»." ;;
    Sfera-Setup-macOS-ARM-*.dmg)
      NAME="$BASE"; TITLE="Сфера для macOS: Apple Silicon"
      DESC="Образ диска для Mac с чипами M1 и новее. Откройте и перетащите «Панель Сферы» в «Программы». При первом запуске нажмите правой кнопкой → «Открыть»." ;;
    Sfera-Setup-Linux-*.deb)
      NAME="$BASE"; TITLE="Сфера для Linux: пакет .deb"
      DESC="Пакет для Ubuntu, Debian и производных. Установка: sudo apt install ./$BASE. Зависимости подтянутся сами, пункт «Панель Сферы» появится в меню приложений." ;;
    Sfera-Panel-Windows.zip)
      NAME="Sfera-Panel-Windows-$VER.zip"; TITLE="Сфера для Windows: архив"
      DESC="Портативная версия без установщика: распакуйте в любую папку и запустите Sfera-Panel.exe. Из этого архива панель обновляет сама себя." ;;
    Sfera-Panel-macOS-Intel.zip)
      NAME="Sfera-Panel-macOS-Intel-$VER.zip"; TITLE="Сфера для macOS: архив (Intel)"
      DESC="Приложение в архиве для Mac с процессором Intel. Распакуйте и перенесите в «Программы». Из этого архива панель обновляет сама себя." ;;
    Sfera-Panel-macOS.zip)
      NAME="Sfera-Panel-macOS-ARM-$VER.zip"; TITLE="Сфера для macOS: архив (Apple Silicon)"
      DESC="Приложение в архиве для Mac с чипами M1 и новее. Распакуйте и перенесите в «Программы». Из этого архива панель обновляет сама себя." ;;
    Sfera-Panel-Linux.tar.xz)
      NAME="Sfera-Panel-Linux-$VER.tar.xz"; TITLE="Сфера для Linux: архив"
      DESC="Для дистрибутивов без .deb. Установите llvm-18, clang, libsdl2, libsdl2-ttf и запустите ./Sfera-Panel.sh." ;;
    Sfera-Panel-Android.apk)
      NAME="Sfera-$VER.apk"; TITLE="Сфера для Android"
      DESC="Редактор, запуск программ прямо на телефоне, документация и уроки без интернета. Разрешите установку из браузера или файлового менеджера; обновления ставятся поверх." ;;
    *) continue ;;
  esac
  case "$NAME" in *"-$VER"*) ;; *) echo "Пропускаю $BASE: версия в имени ($NAME) не совпадает с $VER"; ERRS=$((ERRS+1)); continue ;; esac
  SUM=$(shasum -a 256 "$FILE" 2>/dev/null || sha256sum "$FILE"); SUM=${SUM%% *}
  SIZE=$(du -h "$FILE" | cut -f1)
  if [ "$DRY" = 1 ]; then
    echo "• $BASE → $NAME  ($SIZE)"; echo "    $TITLE"; continue
  fi
  echo "• Загружаю $NAME ($SIZE)…"
  send() {
    curl -sS -o "$TMP/resp" -w '%{http_code}' -X PUT -T "$FILE" \
      -H "Authorization: Bearer $TOKEN" \
      -H "X-Title: $(enc "$TITLE")" -H "X-Description: $(enc "$DESC")" -H "X-Sha256: $SUM" \
      "$UP/$NAME" || echo 000
  }
  CODE=$(send)
  if [ "$CODE" = 409 ] && [ "$REPLACE" = 1 ]; then
    curl -sS -o /dev/null -X DELETE -H "Authorization: Bearer $TOKEN" "$UP/$NAME" || true
    CODE=$(send)
  fi
  if [ "$CODE" = 200 ] || [ "$CODE" = 201 ]; then
    echo "    готово"; OK=$((OK+1))
  elif [ "$CODE" = 409 ]; then
    echo "    уже есть на сайте (используйте --заменить, чтобы перезаписать)"; ERRS=$((ERRS+1))
  else
    echo "    ошибка $CODE: $(cat "$TMP/resp" 2>/dev/null)"; ERRS=$((ERRS+1))
  fi
done < "$LIST"
echo
if [ "$DRY" = 1 ]; then echo "Это была проверка: на сайт ничего не отправлено."; else
  echo "Загружено: $OK, проблем: $ERRS."; echo "Страница загрузок: $SITE/%D0%B7%D0%B0%D0%B3%D1%80%D1%83%D0%B7%D0%BA%D0%B8"; fi
[ "$ERRS" = 0 ]
