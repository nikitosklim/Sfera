#!/bin/bash
# собрать.sh — пересобирает компилятор «Сфера» и обновляет установленные
# команды: запустить, сфера_lsp, сфера_пакеты и стандартную библиотеку.
# Работает на macOS и Linux. Запускать из корня репозитория:
#
#   ./собрать.sh                       # установка в /usr/local (спросит пароль sudo)
#   PREFIX="$HOME/.sfera" ./собрать.sh # установка в свою папку, без sudo
#
# Свежие исходники подтягивайте отдельно:  git pull
# Если ставили в свою папку, добавьте <папка>/bin в PATH (панель делает это сама).

set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
PREFIX="${PREFIX:-/usr/local}"

# Где LLVM 18: Homebrew на macOS или системный пакет на Linux.
if [ -z "$LLVM_SYS_180_PREFIX" ]; then
    if command -v brew >/dev/null 2>&1 && brew list llvm@18 >/dev/null 2>&1; then
        export LLVM_SYS_180_PREFIX=$(brew --prefix llvm@18)
    elif [ -d /usr/lib/llvm-18 ]; then
        export LLVM_SYS_180_PREFIX=/usr/lib/llvm-18
    else
        echo "Не найден LLVM 18. macOS: brew install llvm@18. Ubuntu: sudo apt install llvm-18-dev."
        exit 1
    fi
fi

echo "1/3  Пересобираю компилятор (cargo build --release)..."
cargo build --release

echo "2/3  Обновляю команды в $PREFIX/bin ..."
SUDO=""
if ! mkdir -p "$PREFIX/bin" "$PREFIX/lib/sfera" 2>/dev/null; then SUDO="sudo"; fi
$SUDO mkdir -p "$PREFIX/bin" "$PREFIX/lib/sfera"
for NAME in запустить сфера_lsp сфера_пакеты; do
    $SUDO cp "target/release/$NAME" "$PREFIX/bin/$NAME"
done

echo "3/3  Обновляю стандартную библиотеку в $PREFIX/lib/sfera ..."
$SUDO rm -rf "$PREFIX/lib/sfera/стандартная_библиотека"
$SUDO cp -r стандартная_библиотека "$PREFIX/lib/sfera/стандартная_библиотека"

echo ""
echo "Готово. Версия: $(grep -m1 '^version' Cargo.toml | sed 's/.*\"\(.*\)\".*/\1/')"
echo "Проверка:  запустить examples/привет.код"
