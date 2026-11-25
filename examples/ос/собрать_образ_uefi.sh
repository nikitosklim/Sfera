#!/bin/sh
# Собирает образ диска/флешки для загрузки по UEFI: таблица разделов GPT и раздел EFI (FAT) с нашим загрузчиком,
# в который вшито ядро. Использование:  ./собрать_образ_uefi.sh ядро.elf образ.img
# Требуется: clang, lld-link, objcopy, nm, python3, sfdisk (util-linux), mtools.
# Проверка в QEMU:  qemu-system-x86_64 -bios /usr/share/ovmf/OVMF.fd -drive file=образ.img,format=raw -m 128M
# На флешку (ОСТОРОЖНО: сотрёт её; /dev/sdX — именно флешка!):  sudo dd if=образ.img of=/dev/sdX bs=4M conv=fsync
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
ELF="$1"
OUT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
WORK=$(mktemp -d)
"$DIR/uefi/собрать_uefi.sh" "$ELF" "$WORK/BOOTX64.EFI" >/dev/null
rm -f "$OUT"
truncate -s 64M "$OUT"
echo 'label: gpt
start=2048, type=U' | sfdisk -q "$OUT"
mformat -i "$OUT@@1M" -F -v СФЕРА ::
mmd -i "$OUT@@1M" ::/EFI ::/EFI/BOOT
mcopy -i "$OUT@@1M" "$WORK/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
echo "готово: $OUT"
