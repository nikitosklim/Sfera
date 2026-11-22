#!/usr/bin/env bash
# Собирает игру на Сфере (подключить игра;) в папку для публикации в браузере.
# Использование: ./собрать-игру.sh игры/змейка.код [компилятор]
# Результат: папка <имя>-веб/ (index.html, игра.wasm, игра-хост.js) и архив <имя>-веб.zip
# для загрузки на itch.io (тип проекта «HTML», отметить «This file will be played in the browser»).
set -euo pipefail
SRC="${1:?укажите файл игры, например: $0 игры/змейка.код}"
HERE="$(cd "$(dirname "$0")" && pwd)"
COMP="${2:-$HERE/target/release/запустить}"
[ -x "$COMP" ] || компилятор="$(command -v сфера || true)"
[ -n "$COMP" ] || { echo "Не найден компилятор Сферы. Передайте путь вторым аргументом."; exit 1; }
NAME="$(basename "$SRC" .код)"
OUT="$(dirname "$SRC")/$NAME-веб"
WORK="$(mktemp -d)"
cp "$SRC" "$WORK/$NAME.код"
( cd "$WORK" && "$COMP" "$NAME.код" -c --целевая-платформа wasm32-wasi --wasm-хост )
rm -rf "$OUT" && mkdir -p "$OUT"
cp "$WORK/$NAME" "$OUT/игра.wasm"
cp "$HERE/сайт/static/игра-хост.js" "$OUT/игра-хост.js"
cat > "$OUT/index.html" <<HTML
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$NAME</title>
<style>
html,body{margin:0;height:100%;background:#111;display:flex;align-items:center;justify-content:center}
canvas{max-width:100%;max-height:100%;image-rendering:pixelated;outline:none}
</style>
</head>
<body>
<canvas id="игра" tabindex="0"></canvas>
<script src="игра-хост.js" data-wasm="игра.wasm"></script>
</body>
</html>
HTML
rm -rf "$WORK"
( cd "$(dirname "$OUT")" && rm -f "$NAME-веб.zip" && cd "$(basename "$OUT")" && zip -qr "../$NAME-веб.zip" . )
echo "Готово: $OUT и $(dirname "$OUT")/$NAME-веб.zip"
