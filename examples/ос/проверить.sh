#!/bin/sh
# Собирает мини-ОС на Сфере, запускает в QEMU без окна, «набирает» команды на клавиатуре,
# сверяет вывод последовательного порта с ос.ожидание и снимок экрана — с ос.экран.md5.
# Режим «диск»:  ./проверить.sh диск  — ядро грузится с образа диска нашим загрузчиком (без -kernel).
# Режим «sata»:  ./проверить.sh sata  — диск с файлами подключён как SATA (контроллер AHCI), а не IDE.
# Режим «uefi»:  ./проверить.sh uefi  — загрузка через UEFI (прошивка OVMF, наш загрузчик uefi/BOOTX64.EFI), диск SATA.
# Требуется: qemu-system-x86_64, as, ld, собранный компилятор. Память QEMU — 64 МБ.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
SFERA="${SFERA_BIN:-$DIR/../../target/release/запустить}"
WORK=$(mktemp -d)
cd "$WORK"
"$DIR/собрать_ядро.sh" "$WORK/ос.bin"
rm -f ос.вывод экран.ppm
DATA="-drive file=данные.img,format=raw,if=ide,index=2"
SATA="-device ich9-ahci,id=ahci -drive file=данные.img,if=none,id=d0,format=raw -device ide-hd,drive=d0,bus=ahci.0"
WAIT=1
EXPECT="$DIR/ос.ожидание"
EXPECT_SCREEN="$DIR/ос.экран.md5"
if [ "$1" = "диск" ]; then
    "$DIR/собрать_образ.sh" ос.bin диск.img >/dev/null
    BOOT="-drive format=raw,file=диск.img"
    TITLE="мини-ОС с диска"
elif [ "$1" = "sata" ]; then
    BOOT="-kernel ос.bin"
    DATA="$SATA"
    TITLE="мини-ОС, диск SATA"
elif [ "$1" = "uefi" ]; then
    mkdir -p esp/EFI/BOOT
    "$DIR/uefi/собрать_uefi.sh" ос.bin esp/EFI/BOOT/BOOTX64.EFI >/dev/null
    BOOT="-bios /usr/share/ovmf/OVMF.fd -drive file=fat:rw:esp,format=raw"
    DATA="$SATA"
    WAIT=18
    EXPECT="$DIR/ос.ожидание_uefi"
    EXPECT_SCREEN="$DIR/ос.экран_uefi.md5"
    TITLE="мини-ОС через UEFI"
else
    BOOT="-kernel ос.bin"
    TITLE="мини-ОС"
fi
# F1 (русская раскладка), «помощь», Enter, Shift+В Shift+Ы, Enter, «память», «страницы», «память»,
# «задачи», «программа» (кольцо 3), «нарушение» (защита памяти), «создать/показать/удалить» (запись файлов на диск), «сбой» (ошибка страницы → паника), снимок экрана, выход из QEMU
( sleep $WAIT
  # ждём приглашения ядра (под UEFI загрузка прошивки занимает разное время)
  N=0; until grep -aq 'сфера>' ос.вывод 2>/dev/null || [ $N -ge 120 ]; do sleep 0.5; N=$((N+1)); done; sleep 1
  for K in f1 g j v j o m ret shift-d shift-s ret g f v z n m ret c n h f y b w s ret g f v z n m ret p f l f x b ret g h j u h f v v f ret y f h e i t y b t ret a f q k s ret p f g e c n b n m spc g h b d t n ret p f g e c n b n m spc c x b n f k r f ret p f g e c n b n m spc y t n ret c j p l f n m spc f spc g h b d t n spc v b h ret g j r f p f n m spc f ret c j p l f n m spc f spc n t c n ret g j r f p f n m spc f ret e l f k b n m spc f ret a f q k s ret c comma j q ret; do echo "sendkey $K"; sleep 0.15; done
  sleep 1; echo "screendump $WORK/экран.ppm"; sleep 0.5; echo quit ) | timeout 100 qemu-system-x86_64 -m 64M $BOOT $DATA -vga std -display none -serial "file:ос.вывод" -monitor stdio -no-reboot >/dev/null 2>&1 || true
if [ "$1" = "uefi" ]; then
    # в последовательный порт пишет и прошивка (её сообщения и управляющие коды) — оставляем вывод ядра
    sed -n '/^Сфера ОС 0.2/,$p' ос.вывод > ос.вывод.чистый && mv ос.вывод.чистый ос.вывод
fi
RESULT=0
if cmp -s ос.вывод "$EXPECT"; then
    echo "ПРОЙДЕНО: $TITLE, вывод"
else
    echo "НЕ ПРОЙДЕНО: $TITLE, вывод"
    echo "--- получено:"; cat ос.вывод 2>/dev/null || true
    echo "--- ожидалось:"; cat "$EXPECT"
    RESULT=1
fi
SUM=$(md5sum экран.ppm 2>/dev/null | cut -d' ' -f1)
if [ "$SUM" = "$(cat "$EXPECT_SCREEN")" ]; then
    echo "ПРОЙДЕНО: $TITLE, снимок экрана"
else
    echo "НЕ ПРОЙДЕНО: $TITLE, снимок экрана ($SUM)"
    RESULT=1
fi
exit $RESULT
