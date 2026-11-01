#!/bin/sh
# Загружает установщики на страницу «Загрузки» сайта.
# Использование:
#   sh upload-release.sh АДРЕС_САЙТА ВЕРСИЯ файл1 [файл2 ...]
# Пример:
#   sh upload-release.sh https://xn--80ajfm5aev7c8a.xn--p1ai 0.3.3 ~/Downloads/Sfera-Panel-Windows.zip
# Токен берётся из переменной SFERA_TOKEN или из файла ~/.sfera-token
# (токен лежит на сервере: /opt/sfera/сайт/admin-token.txt).
# Тип системы определяется по имени файла: Windows, macOS, Linux, .apk — Android.
# К имени добавляется версия: Sfera-Panel-macOS.zip -> Sfera-Panel-macOS-0.3.3.zip.
# Если в имени есть Intel или arm — это попадёт в название на странице.
set -e
[ $# -ge 3 ] || { sed -n 2,11p "$0"; exit 1; }
SITE="${1%/}"; VER="$2"; shift 2
TOKEN="${SFERA_TOKEN:-$(cat "$HOME/.sfera-token" 2>/dev/null || true)}"
[ -n "$TOKEN" ] || { echo "Нет токена: задайте SFERA_TOKEN или положите его в ~/.sfera-token"; exit 1; }
case "$SITE" in http://*) echo "Внимание: адрес без HTTPS — токен пойдёт по сети открытым текстом!";; esac
enc() { printf '%s' "$1" | perl -pe 's/([^A-Za-z0-9_.~-])/sprintf("%%%02X",ord($1))/ge'; }
for f in "$@"; do
  [ -f "$f" ] || { echo "Файл не найден: $f"; continue; }
  base=$(basename "$f")
  ext="${base##*.}"; stem="${base%.*}"
  case "$base" in *.tar.xz) ext="tar.xz"; stem="${base%.tar.xz}";; *.tar.gz) ext="tar.gz"; stem="${base%.tar.gz}";; esac
  case "$base" in
    *Windows*|*windows*) os="Windows";;
    *macOS*|*macos*)     os="macOS";;
    *Linux*|*linux*)     os="Linux";;
    *.apk)               os="Android";;
    *) echo "Пропускаю $base: не понял систему (в имени должно быть Windows, macOS или Linux, либо .apk)"; continue;;
  esac
  arch=""
  case "$base" in *ntel*) arch=" (Intel)";; *rm64*|*ARM*|*arm*) arch=" (Apple Silicon / ARM)";; esac
  [ "$os" = "Android" ] && arch=" (APK, ARM64)"
  name="${stem}-${VER}.${ext}"
  title="Сфера ${VER} для ${os}${arch}"
  case "$os" in
    Windows) desc="Панель разработчика, компилятор и установщик. Распаковать и запустить Sfera-Panel.exe.";;
    macOS)   desc="Приложение «Панель Сферы». Скопируйте в «Программы», при первом запуске: правая кнопка — «Открыть».";;
    Linux)   desc="Панель разработчика и компилятор для Linux. Распаковать и запустить.";;
    Android) desc="Среда разработки с компилятором на телефоне: редактор, запуск программ, справка внутри.";;
  esac
  sum=$(shasum -a 256 "$f" 2>/dev/null || sha256sum "$f"); sum=${sum%% *}
  echo "Загружаю $base как $name ..."
  code=$(curl -sS -o /tmp/upload-resp.$$ -w '%{http_code}' -X PUT -T "$f" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Title: $(enc "$title")" -H "X-Description: $(enc "$desc")" -H "X-Sha256: $sum" \
    "$SITE/upload/$name") || code=000
  echo "  ответ $code: $(cat /tmp/upload-resp.$$ 2>/dev/null)"; rm -f /tmp/upload-resp.$$
done
echo "Готово. Проверьте страницу: $SITE/downloads"
