#!/bin/bash
# собрать-релиз-linux.sh — собирает архив Sfera-Panel-Linux.tar.xz: панель
# разработчика + компилятор + стандартная библиотека. Запускать из корня
# репозитория на Linux (нужны Rust, LLVM 18, libsdl2-dev, libsdl2-ttf-dev):
#   LLVM_SYS_180_PREFIX=/usr/lib/llvm-18 ./собрать-релиз-linux.sh
#
# Архив соберётся под системную glibc: запускается на Linux с такой же или
# более новой (Ubuntu 24.04+, Fedora 40+).

set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
VERSION=$(grep -m1 '^version' Cargo.toml | sed 's/.*"\(.*\)".*/\1/')

echo "1/4  Собираю компилятор..."
cargo build --release

echo "2/4  Собираю панель разработчика..."
(cd инструменты/панель-разработчика && "$ROOT/target/release/запустить" панель_unix.код --только-собрать --линковать SDL2 --линковать SDL2_ttf --линковать m)

echo "3/4  Раскладываю файлы..."
OUT="$ROOT/релиз"
DIR="$OUT/Sfera-Panel-Linux"
rm -rf "$DIR"
mkdir -p "$DIR/bin" "$DIR/lib/sfera"
cp инструменты/панель-разработчика/панель_unix "$DIR/Sfera-Panel"
for NAME in запустить сфера_lsp сфера_пакеты; do cp "target/release/$NAME" "$DIR/bin/$NAME"; done
cp examples/привет.код "$DIR/bin/привет.код"
cp README.md "$DIR/README.md"
cp -r стандартная_библиотека "$DIR/lib/sfera/стандартная_библиотека"
cat > "$DIR/Sfera-Panel.sh" <<'LAUNCH'
#!/bin/sh
cd "$(dirname "$0")" && exec ./Sfera-Panel
LAUNCH
chmod +x "$DIR/Sfera-Panel" "$DIR/Sfera-Panel.sh" "$DIR"/bin/запустить "$DIR"/bin/сфера_lsp "$DIR"/bin/сфера_пакеты
cat > "$DIR/ЧИТАЙ_МЕНЯ.txt" <<README
Сфера $VERSION — панель разработчика для Linux

1. Установите зависимости (Ubuntu/Debian):
     sudo apt install llvm-18 clang libsdl2-2.0-0 libsdl2-ttf-2.0-0 zenity
2. Запустите панель:   ./Sfera-Panel.sh
3. На вкладке "Обзор" нажмите "Установить Сферу" и выберите папку
   (по умолчанию ~/.sfera). Добавьте <папка>/bin в PATH:
     echo 'export PATH="\$HOME/.sfera/bin:\$PATH"' >> ~/.bashrc
4. Проверка:   запустить --help

Можно обойтись без панели: bin/запустить — это сам компилятор.
Исходный код и документация: https://github.com/nikitosklim/Sfera
README

echo "4/4  Упаковываю..."
strip "$DIR/Sfera-Panel" "$DIR"/bin/запустить "$DIR"/bin/сфера_lsp "$DIR"/bin/сфера_пакеты 2>/dev/null || true
rm -f "$OUT/Sfera-Panel-Linux.tar.gz"
tar -cJf "$OUT/Sfera-Panel-Linux.tar.xz" -C "$OUT" Sfera-Panel-Linux
echo "Готово: $OUT/Sfera-Panel-Linux.tar.xz ($(du -h "$OUT/Sfera-Panel-Linux.tar.xz" | cut -f1))"
