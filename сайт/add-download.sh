#!/bin/sh
# Копирует файл в downloads/ и добавляет строку (с SHA-256) в downloads/list.txt.
# Использование: ./add-download.sh путь/к/файлу "Название" "Описание"
set -e
[ -f "$1" ] || { echo "Файл не найден: $1"; exit 1; }
src=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "$0")"
name=$(basename "$src")
case "$name" in *[!A-Za-z0-9._-]*) echo "Имя файла только латиницей, цифры . _ -"; exit 1;; esac
cp "$src" "downloads/$name"
sum=$(sha256sum "downloads/$name" 2>/dev/null || shasum -a 256 "downloads/$name")
sum=${sum%% *}
echo "$name | ${2:-$name} | ${3:-} | $sum" >> downloads/list.txt
echo "Добавлено: $name ($sum)"
