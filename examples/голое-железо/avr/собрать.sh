#!/bin/sh
# Собирает программу на Сфере для Arduino Uno/Nano (ATmega328P) и, если указан порт, загружает её на плату.
#
# Использование:
#   ./собрать.sh мигалка.код                      — собрать мигалка.hex
#   ./собрать.sh мигалка.код /dev/cu.usbserial-1  — собрать и загрузить
#   MCU=atmega2560 ./собрать.sh ...         — другой процессор (по умолчанию atmega328p)
#   BAUD=57600 ./собрать.sh ...               — для плат со старым загрузчиком (Nano «Old Bootloader»)
#
# Нужны: собранный компилятор Сферы и набор инструментов avr-gcc (компоновщик, avr-objcopy, avrdude).
# Они уже есть внутри Arduino IDE; если ставили её, ничего больше устанавливать не надо.
set -e
FILE="$1"
PORT="$2"
if [ -z "$FILE" ]; then echo "Использование: $0 файл.код [порт]"; exit 1; fi
MCU="${MCU:-atmega328p}"
BAUD="${BAUD:-115200}"
DIR=$(cd "$(dirname "$0")" && pwd)
SFERA="${SFERA_BIN:-$DIR/../../../target/release/запустить}"
[ -x "$SFERA" ] || SFERA=$(command -v запустить || true)
[ -x "$SFERA" ] || { echo "Не найден компилятор Сферы: задайте SFERA_BIN=путь"; exit 1; }

# Инструменты AVR: сначала из PATH, потом из Arduino IDE (macOS, Linux).
find_tool() {
    command -v "$1" 2>/dev/null && return 0
    for base in "$HOME/Library/Arduino15/packages/arduino/tools" "$HOME/.arduino15/packages/arduino/tools"; do
        for p in "$base"/*/*/bin/"$1"; do [ -x "$p" ] && { echo "$p"; return 0; }; done
    done
    return 1
}
GCC=$(find_tool avr-gcc) || { echo "Не найден avr-gcc (поставьте Arduino IDE)"; exit 1; }
OBJCOPY=$(find_tool avr-objcopy) || { echo "Не найден avr-objcopy"; exit 1; }

NAME=$(basename "$FILE" .код)
WORK=$(mktemp -d)
cp "$FILE" "$WORK/$NAME.код"
(cd "$WORK" && "$SFERA" "$NAME.код" --только-собрать --без-ос --целевая-платформа "avr:$MCU" >/dev/null)
"$GCC" -mmcu="$MCU" "$WORK/$NAME.o" -o "$WORK/$NAME.elf"
"$OBJCOPY" -O ihex -R .eeprom "$WORK/$NAME.elf" "$WORK/$NAME.hex"
cp "$WORK/$NAME.hex" "$WORK/$NAME.elf" "$(dirname "$FILE")/"
echo "Готово: $(dirname "$FILE")/$NAME.hex"

if [ -n "$PORT" ]; then
    AVRDUDE=$(find_tool avrdude) || { echo "Не найден avrdude (поставьте Arduino IDE)"; exit 1; }
    CONF=$(dirname "$AVRDUDE")/../etc/avrdude.conf
    if [ -f "$CONF" ]; then
        "$AVRDUDE" -C "$CONF" -p "$MCU" -c arduino -P "$PORT" -b "$BAUD" -U "flash:w:$(dirname "$FILE")/$NAME.hex:i"
    else
        "$AVRDUDE" -p "$MCU" -c arduino -P "$PORT" -b "$BAUD" -U "flash:w:$(dirname "$FILE")/$NAME.hex:i"
    fi
fi
