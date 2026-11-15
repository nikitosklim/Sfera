#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Собирает страницы «Справочник API» из content/api-источник/*.md.

Блок ```код запустить  — программа компилируется и запускается настоящим
компилятором, а её вывод вставляется под примером («Что выведет программа»).
Блок ```код            — просто пример, без запуска.
Запуск: python3 сделать-справочник.py [путь-к-запустить]
"""
import os, re, subprocess, sys, tempfile, pathlib

корень = pathlib.Path(__file__).resolve().parent
источник = корень / "content" / "api-источник"
вывод = корень / "content" / "docs"
запустить = sys.argv[1] if len(sys.argv) > 1 else str(корень.parent / "target" / "release" / "запустить")

блок = re.compile(r"```код( запустить)?\n(.*?)```", re.S)
ошибок = 0

def выполнить(код, имя):
    global ошибок
    with tempfile.TemporaryDirectory() as т:
        f = pathlib.Path(т) / "пример.код"
        f.write_text(код, encoding="utf-8")
        р = subprocess.run([запустить, str(f)], cwd=т, capture_output=True, text=True, timeout=120)
        if р.returncode != 0:
            ошибок += 1
            print(f"ОШИБКА в {имя}:\n{код}\n{р.stdout}{р.stderr}", file=sys.stderr)
            return None
        return р.stdout.rstrip("\n")

# латинское имя страницы -> файл модуля в стандартной_библиотека
модули = {"files": "файлы", "log": "лог", "metrics": "метрики"}

def сигнатуры(имя):
    """Автоматический список: все функции и структуры модуля, как они объявлены."""
    м = модули.get(имя)
    if not м:
        return ""
    код = (корень.parent / "стандартная_библиотека" / (м + ".код")).read_text(encoding="utf-8").splitlines()
    строки = []
    for н, с in enumerate(код):
        if re.match(r"^(экспорт )?(функция|структура) ", с):
            заметка = []
            k = н - 1
            while k >= 0 and код[k].startswith("//"):
                заметка.insert(0, код[k][2:].strip())
                k -= 1
            голова = с.split(" вернуть ")[0].rstrip()
            строки.append((голова, " ".join(заметка)))
    if not строки:
        return ""
    вых = "\n\n## Полный список объявлений\n\nТак эти функции объявлены в исходниках модуля:\n\n```\n"
    вых += "\n".join(г for г, _ in строки) + "\n```\n"
    return вых

for файл in sorted(источник.glob("*.md")):
    текст = файл.read_text(encoding="utf-8")
    def замена(м):
        код = м.group(2)
        запуск = м.group(1)
        результат = "```\n" + код + "```"
        if запуск:
            out = выполнить(код, файл.name)
            if out is not None:
                результат += "\n\n**Что выведет программа:**\n\n```\n" + out + "\n```"
        return результат
    итог = блок.sub(замена, текст)
    итог = итог.replace("<!--", "")  # заготовка
    итог += сигнатуры(файл.stem)
    цель = вывод / f"api-{файл.stem}.md"
    цель.write_text(итог, encoding="utf-8")
    print("записано", цель.name)
sys.exit(1 if ошибок else 0)
