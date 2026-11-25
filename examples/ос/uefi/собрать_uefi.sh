#!/bin/sh
# Собирает UEFI-загрузчик с вшитым ядром:  ./собрать_uefi.sh ядро.elf BOOTX64.EFI
# Результат кладут на раздел EFI (FAT) как EFI/BOOT/BOOTX64.EFI. Требуется: clang, lld-link, objcopy, nm, python3.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
ELF="$1"
OUT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
WORK=$(mktemp -d)
objcopy -O binary "$ELF" "$WORK/ядро_плоское.bin"
ENTRY=$(nm "$ELF" | awk '$3=="_start_uefi" {print $1}')
[ -n "$ENTRY" ] || { echo "в ядре нет _start_uefi"; exit 1; }
echo ".set ENTRY_POINT, 0x$ENTRY" > "$WORK/точка.inc"
python3 - "$WORK/сообщения.inc" <<'P'
import sys
msgs = {
 "msg_start": "SFERA OS: loading kernel...\r\n",
 "msg_nomem": "SFERA OS: cannot reserve memory at 1 MB\r\n",
 "msg_map": "SFERA OS: memory map / ExitBootServices failed\r\n",
}
out = ['.section .rdata,"dr"', '.align 2']
for name, text in msgs.items():
    out.append(f"{name}:")
    out.append("    .2byte " + ", ".join(str(ord(c)) for c in text) + ", 0")
    out.append(".align 2")
out.append('.text')
open(sys.argv[1], "w").write("\n".join(out) + "\n")
P
cd "$WORK"
clang --target=x86_64-pc-windows-msvc -c -x assembler -I"$WORK" -I"$DIR" "$DIR/загрузчик_uefi.s" -o загрузчик.obj
lld-link /subsystem:efi_application /entry:efi_main /nodefaultlib /base:0x10000000 /fixed:no /out:"$OUT" загрузчик.obj >/dev/null
echo "готово: $OUT ($(wc -c < "$OUT") байт)"
