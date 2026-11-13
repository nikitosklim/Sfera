#!/bin/sh
# Собирает программу на Сфере под ARM Cortex-M0, запускает в QEMU (плата virt) без экрана
# и сравнивает вывод последовательного порта с файлом «<имя>.ожидание».
#
# Использование:  ./проверить.sh [имя]
# Требуется: qemu-system-arm, clang и ld.lld (LLVM), собранный компилятор.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
SFERA="${SFERA_BIN:-$DIR/../../../target/release/запустить}"
WORK=$(mktemp -d)

check_one() {
    NAME="$1"
    cp "$DIR/$NAME.код" "$WORK/"
    cd "$WORK"
    clang --target=thumbv6m-none-eabi -mcpu=cortex-m0plus -c "$DIR/запуск_cortex_m0.s" -o запуск.o
    "$SFERA" "$NAME.код" --только-собрать --без-ос --целевая-платформа thumbv6m-none-eabi >/dev/null
    ld.lld -T "$DIR/компоновка_cortex_m0.ld" запуск.o "$NAME.o" -o "$NAME.elf"
    rm -f "$NAME.вывод"
    timeout 20 qemu-system-arm -machine mps2-an385 -kernel "$NAME.elf" -display none -serial "file:$NAME.вывод" -monitor none -semihosting-config enable=on,target=native >/dev/null 2>&1 || true
    if cmp -s "$NAME.вывод" "$DIR/$NAME.ожидание"; then
        echo "ПРОЙДЕНО: Cortex-M0 $NAME"
    else
        echo "НЕ ПРОЙДЕНО: Cortex-M0 $NAME"
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
