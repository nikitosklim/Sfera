#!/bin/sh
# Собирает программу для Raspberry Pi Pico: ./собрать.sh привет_pico   → привет_pico.uf2
# Требуется: clang, ld.lld, llvm-objcopy, python3, собранный компилятор.
# Проверяется только сборка (запуск на настоящей плате не проверялся).
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
SFERA="${SFERA_BIN:-$DIR/../../../target/release/запустить}"
NAME="${1:-привет_pico}"
WORK=$(mktemp -d)
cp "$DIR/$NAME.код" "$WORK/"
cd "$WORK"
clang --target=thumbv6m-none-eabi -mcpu=cortex-m0plus -c "$DIR/запуск_pico.s" -o запуск.o
"$SFERA" "$NAME.код" --только-собрать --без-ос --целевая-платформа thumbv6m-none-eabi >/dev/null
ld.lld -T "$DIR/компоновка_pico.ld" запуск.o "$NAME.o" -o "$NAME.elf"
llvm-objcopy -O binary "$NAME.elf" "$NAME.bin"
OUT="${2:-$OLDPWD/$NAME.uf2}"
python3 "$DIR/в_uf2.py" "$NAME.bin" "$OUT"
