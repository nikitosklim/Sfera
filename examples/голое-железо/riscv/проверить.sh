#!/bin/sh
# Собирает программу на Сфере под RISC-V 64, запускает в QEMU (плата virt) без экрана
# и сравнивает вывод последовательного порта с файлом «<имя>.ожидание».
#
# Использование:  ./проверить.sh [имя]
# Требуется: qemu-system-riscv64, clang и ld.lld (LLVM), собранный компилятор.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
SFERA="${SFERA_BIN:-$DIR/../../../target/release/запустить}"
WORK=$(mktemp -d)

check_one() {
    NAME="$1"
    cp "$DIR/$NAME.код" "$WORK/"
    cd "$WORK"
    clang --target=riscv64-unknown-elf -march=rv64gc -c "$DIR/запуск_riscv64.s" -o запуск.o
    "$SFERA" "$NAME.код" --только-собрать --без-ос --целевая-платформа riscv64-unknown-elf >/dev/null
    ld.lld -T "$DIR/компоновка_riscv64.ld" запуск.o "$NAME.o" -o "$NAME.elf"
    rm -f "$NAME.вывод"
    timeout 20 qemu-system-riscv64 -machine virt -bios none -kernel "$NAME.elf" -display none -serial "file:$NAME.вывод" -monitor none >/dev/null 2>&1 || true
    if cmp -s "$NAME.вывод" "$DIR/$NAME.ожидание"; then
        echo "ПРОЙДЕНО: RISC-V $NAME"
    else
        echo "НЕ ПРОЙДЕНО: RISC-V $NAME"
        echo "--- получено:"; cat "$NAME.вывод" 2>/dev/null || true
        echo "--- ожидалось:"; cat "$DIR/$NAME.ожидание"
        return 1
    fi
}

RESULT=0
if [ -n "$1" ]; then
    check_one "$1" || RESULT=1
else
    for f in "$DIR"/*.ожидание; do
        check_one "$(basename "$f" .ожидание)" || RESULT=1
    done
fi
exit $RESULT
