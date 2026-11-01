#!/usr/bin/env python3
"""Рисует иконку приложения (сфера на тёмном фоне) в нужных размерах."""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

def рисовать(n):
    k = 4
    s = n * k
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # фон — скруглённый квадрат
    d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * 0.22), fill=(27, 31, 46, 255))
    # сфера с радиальным градиентом
    c = s // 2
    r = int(s * 0.34)
    сфера = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = сфера.load()
    lx, ly = c - r * 0.35, c - r * 0.4
    for y in range(c - r, c + r):
        for x in range(c - r, c + r):
            dx, dy = x - c, y - c
            if dx * dx + dy * dy <= r * r:
                t = (((x - lx) ** 2 + (y - ly) ** 2) ** 0.5) / (r * 1.5)
                t = min(1.0, t)
                a = (150, 200, 255); b = (30, 70, 190)
                px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)
    img = Image.alpha_composite(img, сфера)
    d = ImageDraw.Draw(img)
    # блик
    d.ellipse((c - r * 0.62, c - r * 0.7, c - r * 0.2, c - r * 0.36), fill=(255, 255, 255, 70))
    return img.resize((n, n), Image.LANCZOS)

if __name__ == "__main__":
    корень = sys.argv[1] if len(sys.argv) > 1 else "res"
    for имя, n in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        p = os.path.join(корень, "mipmap-" + имя)
        os.makedirs(p, exist_ok=True)
        рисовать(n).save(os.path.join(p, "ic_launcher.png"))
    рисовать(512).save(os.path.join(корень, "иконка-512.png"))
