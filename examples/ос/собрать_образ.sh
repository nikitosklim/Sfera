#!/bin/sh
# Собирает образ диска с загрузчиком Сферы и ядром.
# Использование:  ./собрать_образ.sh ядро.elf образ.img
# Требуется: as, ld, objcopy, readelf (binutils).
# Образ можно запустить в QEMU:  qemu-system-x86_64 -drive format=raw,file=образ.img -m 64M
# или записать на флешку (dd) и загрузить обычный компьютер с BIOS (режим Legacy / CSM).
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
YADRO="$1"
OBRAZ="$2"
WORK=$(mktemp -d)

# ядро как плоский образ памяти, начинающийся с 0x100000
objcopy -O binary "$YADRO" "$WORK/yadro.bin"
SIZE=$(wc -c < "$WORK/yadro.bin")
SIZE4=$(( (SIZE + 3) / 4 * 4 ))
ENTRY=$(readelf -hW "$YADRO" | awk '/Entry point/ {print $4}')
# конец области bss: самый дальний байт по заголовкам программы
readelf -lW "$YADRO" | grep '^  LOAD' > "$WORK/load.txt"
BSSEND=0
while read -r TYPE OFF VADDR PADDR FSZ MSZ REST; do
    E=$(( VADDR + MSZ ))
    if [ "$E" -gt "$BSSEND" ]; then BSSEND=$E; fi
done < "$WORK/load.txt"
KSECT=$(( (SIZE + 511) / 512 ))
KDW=$(( SIZE4 / 4 ))
KEND=$(( 1048576 + SIZE4 ))
BSSDW=$(( (BSSEND - KEND + 3) / 4 ))

# второй этап
# число секторов второго этапа зависит от его размера, а размер ядра в нём — константа: собираем дважды
build_stage2() {
    as --32 -I "$DIR" -I "$DIR/загрузчик" -defsym "ЯДРО_СЕКТОРОВ=$KSECT" -defsym "ЯДРО_ПЕРВЫЙ_СЕКТОР=$1" -defsym "ЯДРО_ДВОЙНЫХ_СЛОВ=$KDW" \
       -defsym "ЯДРО_КОНЕЦ_ОБРАЗА=$KEND" -defsym "BSS_ДВОЙНЫХ_СЛОВ=$BSSDW" -defsym "ЯДРО_ВХОД=$ENTRY" \
       "$DIR/загрузчик/второй_этап.s" -o "$WORK/s2.o"
    ld -m elf_i386 -Ttext 0x7E00 --oformat binary "$WORK/s2.o" -o "$WORK/s2.bin"
}
build_stage2 0
S2SECT=$(( ($(wc -c < "$WORK/s2.bin") + 511) / 512 ))
build_stage2 $(( 1 + S2SECT ))

# первый этап
as --32 -defsym "ЭТАП2_СЕКТОРОВ=$S2SECT" "$DIR/загрузчик/первый_этап.s" -o "$WORK/s1.o"
ld -m elf_i386 -Ttext 0x7C00 --oformat binary "$WORK/s1.o" -o "$WORK/s1.bin"

# образ: загрузочный сектор, второй этап, ядро, добивка до 1 МБ
cp "$WORK/s1.bin" "$OBRAZ"
dd if="$WORK/s2.bin" of="$OBRAZ" bs=512 seek=1 conv=notrunc 2>/dev/null
dd if="$WORK/yadro.bin" of="$OBRAZ" bs=512 seek=$(( 1 + S2SECT )) conv=notrunc 2>/dev/null
truncate -s 1048576 "$OBRAZ"
echo "Образ готов: $OBRAZ (ядро $SIZE байт, второй этап $S2SECT секторов)"
