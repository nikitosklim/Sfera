#!/usr/bin/env python3
"""в_uf2.py — упаковывает двоичный образ в формат UF2 для RP2040 (загрузка в оперативную память).
Использование: в_uf2.py программа.bin программа.uf2 [адрес]   (адрес по умолчанию 0x20000000)
Файл .bin получают так:  llvm-objcopy -O binary программа.elf программа.bin
Образ копируется на диск RPI-RP2, который появляется при подключении Pico с зажатой кнопкой BOOTSEL."""
import struct, sys

def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    данные = open(sys.argv[1], "rb").read()
    адрес = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x20000000
    блоков = (len(данные) + 255) // 256
    выход = bytearray()
    for н in range(блоков):
        кусок = данные[н * 256:(н + 1) * 256].ljust(256, b"\0")
        заголовок = struct.pack("<8I", 0x0A324655, 0x9E5D5157, 0x00002000, адрес + н * 256, 256, н, блоков, 0xE48BFF56)
        выход += заголовок + кусок + b"\0" * (476 - 256) + struct.pack("<I", 0x0AB16F30)
    open(sys.argv[2], "wb").write(выход)
    print(f"{sys.argv[2]}: {блоков} блоков, {len(данные)} байт")

main()
