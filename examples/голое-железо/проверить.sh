#!/bin/sh
# Собирает программу на Сфере вместе со стартовым кодом x86-64, запускает в QEMU без экрана
# и сравнивает вывод последовательного порта с файлом «<имя>.ожидание».
#
# Использование:  ./проверить.sh [имя]        (без имени проверяет все примеры)
# Требуется: qemu-system-x86_64, as, ld, собранный компилятор (cargo build --release).
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
SFERA="${SFERA_BIN:-$DIR/../../target/release/запустить}"
LIB="$DIR/../../стандартная_библиотека"
WORK=$(mktemp -d)

check_one() {
    NAME="$1"
    cp "$DIR/$NAME.код" "$WORK/"
    cd "$WORK"
    as "$DIR/запуск_х86_64.s" -o запуск.o
    "$SFERA" "$NAME.код" --только-собрать --без-ос >/dev/null
    ld -m elf_x86_64 -T "$DIR/компоновка_ядра_64.ld" запуск.o "$NAME.o" -o "$NAME.bin" 2>/dev/null
    rm -f "$NAME.вывод"
    timeout 20 qemu-system-x86_64 -kernel "$NAME.bin" -display none -serial "file:$NAME.вывод" -no-reboot >/dev/null 2>&1 || true
    if cmp -s "$NAME.вывод" "$DIR/$NAME.ожидание"; then
        echo "ПРОЙДЕНО: $NAME"
    else
        echo "НЕ ПРОЙДЕНО: $NAME"
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
