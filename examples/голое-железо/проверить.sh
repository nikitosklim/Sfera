#!/bin/sh
# Собирает ядро с примером на Сфере и запускает его в QEMU без экрана.
# Проверяет, что программа вывела «Hi 4000000000» через последовательный порт COM1.
# Требуется: qemu-system-x86_64, as, ld, собранный компилятор (cargo build --release).
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
SFERA="${SFERA:-$DIR/../../target/release/запустить}"
NAME="${1:-серийный_порт}"
WORK=$(mktemp -d)
cp "$DIR/$NAME.код" "$WORK/"
cd "$WORK"
as "$DIR/ядро_64.s" -o ядро.o
"$SFERA" "$NAME.код" --только-собрать --без-ос
ld -m elf_x86_64 -T "$DIR/компоновка_ядра_64.ld" ядро.o "$NAME.o" -o ядро.bin 2>/dev/null
timeout 5 qemu-system-x86_64 -kernel ядро.bin -display none -serial file:вывод.txt -no-reboot >/dev/null 2>&1 || true
cat вывод.txt
grep -q "Hi 4000000000" вывод.txt && echo "ПРОВЕРКА ПРОЙДЕНА" || { echo "ПРОВЕРКА НЕ ПРОЙДЕНА"; exit 1; }
