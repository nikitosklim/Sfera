#!/usr/bin/env python3
"""Рисует иконку Сферы (чёрный шар «8» на плитке цвета «Синей стали») и раскладывает по платформам:
macOS (.icns), Windows (.ico), Linux (PNG), Android (mipmap + adaptive), сайт, расширение VS Code.
Запуск из корня репозитория:  python3 инструменты/иконки/сделать-иконки.py .
Нужны: python3, Pillow, playwright с chromium (рисует SVG)."""
import os, sys, math, struct, shutil, tempfile
from PIL import Image
from playwright.sync_api import sync_playwright

def ball(cx, cy, r, uid):
    # чёрный глянцевый шар «8» (лучше всего читается на тёмно-синем фоне)
    return f'''
<defs>
 <radialGradient id="b{uid}" cx="38%" cy="30%" r="80%" fx="34%" fy="26%">
  <stop offset="0" stop-color="#4a5468"/><stop offset=".18" stop-color="#242b3a"/>
  <stop offset=".6" stop-color="#0b0e15"/><stop offset="1" stop-color="#000"/>
 </radialGradient>
 <radialGradient id="rim{uid}" cx="50%" cy="50%" r="50%">
  <stop offset=".82" stop-color="#3b9cff" stop-opacity="0"/><stop offset="1" stop-color="#6fb4ff" stop-opacity=".35"/>
 </radialGradient>
 <radialGradient id="w{uid}" cx="40%" cy="35%" r="75%">
  <stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#c9d0dc"/>
 </radialGradient>
 <linearGradient id="g{uid}" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#fff" stop-opacity=".85"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
 </linearGradient>
 <clipPath id="c{uid}"><circle cx="{cx}" cy="{cy}" r="{r}"/></clipPath>
</defs>
<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#b{uid})"/>
<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#rim{uid})"/>
<g clip-path="url(#c{uid})">
 <ellipse cx="{cx-r*.14}" cy="{cy-r*.2}" rx="{r*.47}" ry="{r*.47}" fill="url(#w{uid})"/>
 <text x="{cx-r*.14}" y="{cy-r*.2+r*.2}" font-family="DejaVu Sans, Arial, sans-serif" font-weight="700" font-size="{r*.62}" text-anchor="middle" fill="#0b0e15">8</text>
 <ellipse cx="{cx-r*.22}" cy="{cy-r*.62}" rx="{r*.5}" ry="{r*.24}" fill="url(#g{uid})" transform="rotate(-18 {cx-r*.22} {cy-r*.62})"/>
</g>'''

def squircle(x, y, w, h, n=5.0, pts=200):
    cx, cy, a, b = x+w/2, y+h/2, w/2, h/2
    out = []
    for i in range(pts):
        t = 2*math.pi*i/pts
        c, s = math.cos(t), math.sin(t)
        px = cx + a*math.copysign(abs(c)**(2/n), c)
        py = cy + b*math.copysign(abs(s)**(2/n), s)
        out.append(f"{px:.2f},{py:.2f}")
    return "M" + " L".join(out) + " Z"

DEFS = '''<defs>
<linearGradient id="t" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#21407a"/><stop offset=".55" stop-color="#122349"/><stop offset="1" stop-color="#0a1226"/></linearGradient>
<linearGradient id="gl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".16"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/></linearGradient>
<filter id="sh" x="-20%" y="-20%" width="140%" height="150%"><feGaussianBlur stdDeviation="14"/></filter>
<filter id="bs" x="-30%" y="-30%" width="160%" height="170%"><feGaussianBlur stdDeviation="10"/></filter></defs>'''

def svg(kind):
    S = 1024
    if kind == 'mac':      # плитка 824 (стандарт macOS), тень, шар внутри
        d = squircle(100, 100, 824, 824)
        body = (f'<path d="{d}" fill="#000" opacity=".38" transform="translate(0 12)" filter="url(#sh)"/>'
                f'<path d="{d}" fill="url(#t)"/><path d="{d}" fill="url(#gl)"/>'
                f'<circle cx="512" cy="560" r="262" fill="#000" opacity=".5" filter="url(#bs)"/>' + ball(512, 530, 262, 1))
    elif kind == 'flat':   # Windows / Linux / сайт: плитка почти во весь холст (≈94%)
        d = squircle(30, 30, 964, 964, 5.0)
        body = (f'<path d="{d}" fill="url(#t)"/><path d="{d}" fill="url(#gl)"/>'
                f'<circle cx="512" cy="560" r="300" fill="#000" opacity=".5" filter="url(#bs)"/>' + ball(512, 524, 300, 1))
    elif kind == 'fg':     # Android adaptive: шар в безопасной зоне 66/108
        body = ball(512, 512, 250, 1)
        return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">{DEFS}<circle cx="512" cy="542" r="250" fill="#000" opacity=".5" filter="url(#bs)"/>{body}</svg>'
    elif kind == 'bg':
        return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">{DEFS}<rect width="{S}" height="{S}" fill="url(#t)"/><rect width="{S}" height="{S}" fill="url(#gl)"/></svg>'
    elif kind == 'round':  # Android legacy round
        body = (f'<circle cx="512" cy="512" r="512" fill="url(#t)"/><circle cx="512" cy="512" r="512" fill="url(#gl)"/>'
                f'<circle cx="512" cy="562" r="290" fill="#000" opacity=".5" filter="url(#bs)"/>' + ball(512, 528, 290, 1))
    elif kind == 'sq':
        body = (f'<rect width="1024" height="1024" fill="url(#t)"/><rect width="1024" height="1024" fill="url(#gl)"/>'
                f'<circle cx="512" cy="562" r="330" fill="#000" opacity=".5" filter="url(#bs)"/>' + ball(512, 524, 330, 1))
    elif kind == 'small':  # 16/32: без теней и бликов, шар крупнее
        d = squircle(0, 0, 1024, 1024, 5.0)
        body = f'<path d="{d}" fill="#14274f"/>' + ball(512, 512, 372, 1)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">{DEFS}{body}</svg>'


def упаковать_icns(пути, выход):
    типы = {16: b'icp4', 32: b'icp5', 64: b'icp6', 128: b'ic07', 256: b'ic08', 512: b'ic09', 1024: b'ic10'}
    # (размер файла, тип): обычные и @2x
    части = [(16, b'icp4'), (32, b'icp5'), (128, b'ic07'), (256, b'ic08'), (512, b'ic09'), (1024, b'ic10'),
             (32, b'ic11'), (64, b'ic12'), (256, b'ic13'), (512, b'ic14')]
    тело = b''
    for n, т in части:
        данные = open(пути[n], 'rb').read()
        тело += т + struct.pack('>I', len(данные) + 8) + данные
    open(выход, 'wb').write(b'icns' + struct.pack('>I', len(тело) + 8) + тело)

def упаковать_ico(пути, выход):
    размеры = sorted(пути)
    данные = [open(пути[n], 'rb').read() for n in размеры]
    смещение = 6 + 16 * len(размеры)
    заг = struct.pack('<HHH', 0, 1, len(размеры)); записи = b''
    for n, д in zip(размеры, данные):
        записи += struct.pack('<BBBBHHII', n % 256, n % 256, 0, 0, 1, 32, len(д), смещение)
        смещение += len(д)
    open(выход, 'wb').write(заг + записи + b''.join(данные))

if __name__ == '__main__':
    корень = sys.argv[1] if len(sys.argv) > 1 else '.'
    tmp = tempfile.mkdtemp()
    задачи = []  # (вид, размер, файл)
    for n in (16, 32, 64, 128, 256, 512, 1024): задачи.append(('mac', n, f'mac-{n}.png'))
    for n in (16, 24, 32, 48, 64, 128, 180, 192, 256, 512): задачи.append(('flat', n, f'flat-{n}.png'))
    for n in (16, 24, 32, 48, 64): задачи.append(('small', n, f'small-{n}.png'))
    задачи.append(('sq', 180, 'sq-180.png'))
    for n in (108, 162, 216, 324, 432): задачи += [('fg', n, f'fg-{n}.png'), ('bg', n, f'bg-{n}.png')]
    for n in (48, 72, 96, 144, 192): задачи += [('flat', n, f'leg-{n}.png'), ('round', n, f'round-{n}.png')]
    with sync_playwright() as p:
        br = p.chromium.launch(); pg = br.new_page(viewport={'width': 1024, 'height': 1024}); видели = set()
        for вид, n, fn in задачи:
            if вид in видели: continue
            видели.add(вид)
            pg.set_content(f'<html><body style="margin:0;background:transparent">{svg(вид)}</body></html>')
            pg.screenshot(path=f'{tmp}/_{вид}.png', omit_background=True, clip={'x': 0, 'y': 0, 'width': 1024, 'height': 1024})
        br.close()
    for вид, n, fn in задачи:
        Image.open(f'{tmp}/_{вид}.png').convert('RGBA').resize((n, n), Image.LANCZOS).save(f'{tmp}/{fn}')
    T = lambda f: f'{tmp}/{f}'
    def в(путь, что):
        путь = os.path.join(корень, путь); os.makedirs(os.path.dirname(путь), exist_ok=True)
        shutil.copyfile(T(что), путь)
    # macOS
    упаковать_icns({n: T(f'mac-{n}.png') for n in (16, 32, 64, 128, 256, 512, 1024)}, os.path.join(корень, 'инструменты/иконки/Sfera.icns'))
    # Windows: мелкие размеры — упрощённый вариант, крупные — полный
    ico = {n: T(f'small-{n}.png') for n in (16, 24, 32, 48)}
    ico.update({n: T(f'flat-{n}.png') for n in (64, 128, 256)})
    упаковать_ico(ico, os.path.join(корень, 'инструменты/иконки/Sfera.ico'))
    # Linux и окно SDL
    for n in (16, 24, 32, 48, 64, 128, 256, 512):
        в(f'инструменты/иконки/linux/{n}x{n}.png', f'small-{n}.png' if n <= 32 else f'flat-{n}.png')
    Image.open(T('flat-64.png')).save(os.path.join(корень, 'инструменты/иконки/окно.png'))
    # иконка окна SDL (Linux/Windows): BMP с альфа-каналом, лежит рядом с панелью
    import subprocess
    subprocess.run(['convert', os.path.join(корень, 'инструменты/иконки/окно.png'), '-define', 'bmp:format=bmp4',
                    os.path.join(корень, 'инструменты/иконки/окно.bmp')], check=True)
    # сайт
    open(os.path.join(корень, 'сайт/static/logo.svg'), 'w').write(svg('small'))
    ф = lambda n: f'small-{n}.png' if n <= 32 else f'flat-{n}.png'
    упаковать_ico({16: T('small-16.png'), 32: T('small-32.png'), 48: T('small-48.png'), 64: T('flat-64.png')}, os.path.join(корень, 'сайт/static/favicon.ico'))
    в('сайт/static/apple-touch-icon.png', 'sq-180.png')
    в('сайт/static/icon-192.png', 'flat-192.png'); в('сайт/static/icon-512.png', 'flat-512.png'); в('сайт/static/logo.png', 'flat-64.png')
    в('инструменты/sfera-vscode/images/icon.png', 'flat-128.png')
    # Android: обычные (старые системы), круглые и «адаптивные» (Android 8+)
    for имя, d in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        в(f'инструменты/android/apk/res/mipmap-{имя}/ic_launcher.png', f'leg-{d}.png')
        в(f'инструменты/android/apk/res/mipmap-{имя}/ic_launcher_round.png', f'round-{d}.png')
    for имя, d in (('mdpi', 108), ('hdpi', 162), ('xhdpi', 216), ('xxhdpi', 324), ('xxxhdpi', 432)):
        в(f'инструменты/android/apk/res/mipmap-{имя}/ic_launcher_foreground.png', f'fg-{d}.png')
        в(f'инструменты/android/apk/res/mipmap-{имя}/ic_launcher_background.png', f'bg-{d}.png')
    адаптивная = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""
    for имя in ('ic_launcher', 'ic_launcher_round'):
        путь = os.path.join(корень, f'инструменты/android/apk/res/mipmap-anydpi-v26/{имя}.xml')
        os.makedirs(os.path.dirname(путь), exist_ok=True); open(путь, 'w').write(адаптивная)
    print('Готово')
