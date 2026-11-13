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

PANEL_VERSION=$(grep -A1 'функция текущая_версия' инструменты/панель-разработчика/панель_unix.код | grep -o '"[^"]*"' | head -1 | tr -d '"')
[ -n "$PANEL_VERSION" ] || PANEL_VERSION="$VERSION"

echo "1/5  Собираю компилятор..."
cargo build --release

echo "2/5  Собираю панель разработчика..."
(cd инструменты/панель-разработчика && "$ROOT/target/release/запустить" панель_unix.код --только-собрать --линковать SDL2 --линковать SDL2_ttf --линковать m)

echo "3/5  Раскладываю файлы..."
OUT="$ROOT/релиз"
DIR="$OUT/Sfera-Panel-Linux"
rm -rf "$DIR"
mkdir -p "$DIR/bin" "$DIR/lib/sfera"
cp инструменты/панель-разработчика/панель_unix "$DIR/Sfera-Panel"
for NAME in запустить сфера_lsp сфера_пакеты сфера; do cp "target/release/$NAME" "$DIR/bin/$NAME"; done
cp examples/привет.код "$DIR/bin/привет.код"
cp README.md "$DIR/README.md"
cp инструменты/иконки/окно.bmp "$DIR/Sfera-Panel.bmp"
mkdir -p "$DIR/icons"
cp инструменты/иконки/linux/*.png "$DIR/icons/"
cp -r стандартная_библиотека "$DIR/lib/sfera/стандартная_библиотека"
cat > "$DIR/Sfera-Panel.sh" <<'LAUNCH'
#!/bin/sh
cd "$(dirname "$0")" && exec ./Sfera-Panel
LAUNCH
chmod +x "$DIR/Sfera-Panel" "$DIR/Sfera-Panel.sh" "$DIR"/bin/запустить "$DIR"/bin/сфера_lsp "$DIR"/bin/сфера_пакеты "$DIR"/bin/сфера
# Ярлык для меню приложений (с иконкой): ./Установить-ярлык.sh
cat > "$DIR/Установить-ярлык.sh" <<'DESKTOP'
#!/bin/sh
# Добавляет «Панель Сферы» в меню приложений текущего пользователя.
D=$(cd "$(dirname "$0")" && pwd)
for N in 16 24 32 48 64 128 256 512; do
    mkdir -p "$HOME/.local/share/icons/hicolor/${N}x${N}/apps"
    cp "$D/icons/${N}x${N}.png" "$HOME/.local/share/icons/hicolor/${N}x${N}/apps/sfera-panel.png"
done
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/sfera-panel.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=Панель Сферы
Comment=Установка и обновление языка Сфера
Exec=$D/Sfera-Panel.sh
Path=$D
Icon=sfera-panel
Terminal=false
Categories=Development;
ENTRY
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null
echo "Готово: «Панель Сферы» появилась в меню приложений."
DESKTOP
chmod +x "$DIR/Установить-ярлык.sh"
cat > "$DIR/ЧИТАЙ_МЕНЯ.txt" <<README
Сфера $VERSION — панель разработчика для Linux

1. Установите зависимости (Ubuntu/Debian):
     sudo apt install llvm-18 clang libsdl2-2.0-0 libsdl2-ttf-2.0-0 zenity
2. Запустите панель:   ./Sfera-Panel.sh
   (значок в меню приложений: ./Установить-ярлык.sh)
3. На вкладке "Обзор" нажмите "Установить Сферу" и выберите папку
   (по умолчанию ~/.sfera). Добавьте <папка>/bin в PATH:
     echo 'export PATH="\$HOME/.sfera/bin:\$PATH"' >> ~/.bashrc
4. Проверка:   запустить --help

Можно обойтись без панели: bin/запустить — это сам компилятор.
Исходный код и документация: https://github.com/nikitosklim/Sfera
README

echo "4/5  Упаковываю архив..."
strip "$DIR/Sfera-Panel" "$DIR"/bin/запустить "$DIR"/bin/сфера_lsp "$DIR"/bin/сфера_пакеты "$DIR"/bin/сфера 2>/dev/null || true
rm -f "$OUT/Sfera-Panel-Linux.tar.gz"
tar -cJf "$OUT/Sfera-Panel-Linux.tar.xz" -C "$OUT" Sfera-Panel-Linux
echo "Готово: $OUT/Sfera-Panel-Linux.tar.xz ($(du -h "$OUT/Sfera-Panel-Linux.tar.xz" | cut -f1))"

echo "5/5  Собираю установочный пакет (.deb)..."
./инструменты/установщик/собрать-deb.sh "$DIR" "$OUT" "$PANEL_VERSION"
