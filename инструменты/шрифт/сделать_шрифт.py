#!/usr/bin/env python3
"""Делает растровый шрифт 8x16 для мини-ОС: латиница, кириллица, Ё и ё.

Использование:  python3 сделать_шрифт.py  путь/к/DejaVuSansMono.ttf  > шрифт_8х16.s

Глифы берутся из шрифта DejaVu Sans Mono (свободная лицензия Bitstream Vera / DejaVu,
позволяет встраивать глифы в программы; см. https://dejavu-fonts.github.io/License.html).
Порядок глифов: 0–94 — символы 32..126, 95–158 — А…я (U+0410…U+044F), 159 — Ё, 160 — ё, 161 — «, 162 — », 163 — —, 164 — №.
"""
import sys
from PIL import Image, ImageDraw, ImageFont

путь = sys.argv[1]
шрифт = ImageFont.truetype(путь, 13)
коды = list(range(32, 127)) + list(range(0x410, 0x450)) + [0x401, 0x451, 0xAB, 0xBB, 0x2014, 0x2116]
print("# шрифт_8х16.s — создано инструментом сделать_шрифт.py из DejaVu Sans Mono (лицензия Bitstream Vera / DejaVu).")
print("# 161 символ по 16 байт: по одному байту на строку, старший бит — левый пиксель.")
print(".section .rodata")
print(".balign 16")
print(".global sfera_font_8x16")
print("sfera_font_8x16:")
for к in коды:
    картинка = Image.new("1", (8, 16), 0)
    рис = ImageDraw.Draw(картинка)
    рис.fontmode = "1"
    рис.text((0, 12), chr(к), font=шрифт, fill=1, anchor="ls")
    байты = []
    for у in range(16):
        б = 0
        for х in range(8):
            if картинка.getpixel((х, у)):
                б |= 0x80 >> х
        байты.append(б)
    print("    .byte " + ",".join("0x%02X" % б for б in байты) + "   # U+%04X" % к)
