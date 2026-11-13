#!/bin/sh
# Собирает мини-ОС на Сфере, запускает в QEMU без окна, «набирает» команды на клавиатуре,
# сверяет вывод последовательного порта с ос.ожидание и снимок экрана — с ос.экран.md5.
# Режим «диск»:  ./проверить.sh диск  — ядро грузится с образа диска нашим загрузчиком (без -kernel).
# Требуется: qemu-system-x86_64, as, ld, собранный компилятор. Память QEMU — 64 МБ.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
SFERA="${SFERA_BIN:-$DIR/../../target/release/запустить}"
WORK=$(mktemp -d)
cd "$WORK"
"$DIR/собрать_ядро.sh" "$WORK/ос.bin"
rm -f ос.вывод экран.ppm
if [ "$1" = "диск" ]; then
    "$DIR/собрать_образ.sh" ос.bin диск.img >/dev/null
    BOOT="-drive format=raw,file=диск.img"
    TITLE="мини-ОС с диска"
else
    BOOT="-kernel ос.bin"
    TITLE="мини-ОС"
fi
# F1 (русская раскладка), «помощь», Enter, Shift+В Shift+Ы, Enter, «память», «страницы», «память»,
# «задачи», «программа» (кольцо 3), «нарушение» (защита памяти), «сбой» (ошибка страницы → паника), снимок экрана, выход из QEMU
( sleep 1
  for K in f1 g j v j o m ret shift-d shift-s ret g f v z n m ret c n h f y b w s ret g f v z n m ret p f l f x b ret g h j u h f v v f ret y f h e i t y b t ret a f q k s ret p f g e c n b n m spc g h b d t n ret p f g e c n b n m spc c x b n f k r f ret p f g e c n b n m spc y t n ret c comma j q ret; do echo "sendkey $K"; sleep 0.15; done
  sleep 1; echo "screendump $WORK/экран.ppm"; sleep 0.5; echo quit ) | timeout 40 qemu-system-x86_64 -m 64M $BOOT -drive file=данные.img,format=raw,if=ide,index=2 -vga std -display none -serial "file:ос.вывод" -monitor stdio -no-reboot >/dev/null 2>&1 || true
RESULT=0
if cmp -s ос.вывод "$DIR/ос.ожидание"; then
    echo "ПРОЙДЕНО: $TITLE, вывод"
else
    echo "НЕ ПРОЙДЕНО: $TITLE, вывод"
    echo "--- получено:"; cat ос.вывод 2>/dev/null || true
    echo "--- ожидалось:"; cat "$DIR/ос.ожидание"
    RESULT=1
fi
SUM=$(md5sum экран.ppm 2>/dev/null | cut -d' ' -f1)
if [ "$SUM" = "$(cat "$DIR/ос.экран.md5")" ]; then
    echo "ПРОЙДЕНО: $TITLE, снимок экрана"
else
    echo "НЕ ПРОЙДЕНО: $TITLE, снимок экрана ($SUM)"
    RESULT=1
fi
exit $RESULT
