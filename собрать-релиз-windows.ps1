# собрать-релиз-windows.ps1 — собирает для GitHub-релиза готовый архив
# "Sfera-Panel-Windows.zip": панель разработчика + компилятор + всё нужное,
# чтобы человек распаковал архив, запустил Sfera-Panel.exe, нажал
# "Установить Сферу" и получил команду "запустить" в PATH.
#
# Запускать из корня репозитория, в обычном PowerShell (не обязательно от
# администратора), ПОСЛЕ того как установить-windows.ps1 уже отработал на
# этой машине (он ставит Rust, LLVM, SDL2 и pthread_win.o):
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\собрать-релиз-windows.ps1
#
# Имя архива — ASCII и содержит "Windows": панель разработчика при проверке
# обновлений ищет среди файлов релиза имя с меткой платформы "Windows"
# (см. метка_текущей_платформы в панель_windows.код).

param(
    [string]$Версия = "0.3.0"
)

$ErrorActionPreference = "Continue"
$Корень = $PSScriptRoot
$ЛокальнаяСфера = Join-Path $env:LOCALAPPDATA "Сфера"

function Остановить([string]$Сообщение) {
    Write-Host "ОШИБКА: $Сообщение" -ForegroundColor Red
    exit 1
}

# cargo пишет предупреждения в stderr — это не ошибка, статус смотрим по
# коду завершения.
Write-Host "1/5  Собираю компилятор (cargo build --release)..." -ForegroundColor Cyan
Push-Location $Корень
& cargo build --release
if ($LASTEXITCODE -ne 0) { Pop-Location; Остановить "cargo build --release завершился с кодом $LASTEXITCODE" }
Pop-Location

$Релиз = Join-Path $Корень "target\release"
foreach ($имя in @("запустить.exe", "сфера_lsp.exe", "сфера_пакеты.exe")) {
    if (-not (Test-Path (Join-Path $Релиз $имя))) { Остановить "не найден $имя в target\release" }
}

Write-Host "2/5  Собираю панель разработчика..." -ForegroundColor Cyan
$ПапкаПанели = Join-Path $Корень "инструменты\панель-разработчика"
Push-Location $ПапкаПанели
& (Join-Path $Релиз "запустить.exe") "панель_windows.код" --только-собрать --линковать SDL2 --линковать SDL2_ttf --линковать m
if ($LASTEXITCODE -ne 0) { Pop-Location; Остановить "не удалось собрать панель (код $LASTEXITCODE)" }
Pop-Location
$ПанельExe = Join-Path $ПапкаПанели "панель_windows.exe"
if (-not (Test-Path $ПанельExe)) { Остановить "после сборки нет панель_windows.exe" }

Write-Host "3/5  Раскладываю файлы..." -ForegroundColor Cyan
$Выход = Join-Path $Корень "релиз"
$Папка = Join-Path $Выход "Sfera-Panel-Windows"
if (Test-Path $Папка) { Remove-Item -Recurse -Force $Папка }
New-Item -ItemType Directory -Force -Path (Join-Path $Папка "bin") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Папка "lib\sfera") | Out-Null

Copy-Item $ПанельExe (Join-Path $Папка "Sfera-Panel.exe")
foreach ($имя in @("запустить.exe", "сфера_lsp.exe", "сфера_пакеты.exe")) {
    Copy-Item (Join-Path $Релиз $имя) (Join-Path $Папка "bin\$имя")
}
Copy-Item (Join-Path $Корень "examples\привет.код") (Join-Path $Папка "bin\привет.код")

# pthread_win.o — рантайм потоков, без него не слинкуется ни одна программа.
$Pthread = Join-Path $ЛокальнаяСфера "lib\sfera\pthread_win.o"
if (-not (Test-Path $Pthread)) { $Pthread = Join-Path $Корень "рантайм_windows\pthread_win.o" }
if (-not (Test-Path $Pthread)) {
    $Pthread = Join-Path $Выход "pthread_win.o"
    & clang -c (Join-Path $Корень "рантайм_windows\pthread_win.c") -o $Pthread
    if ($LASTEXITCODE -ne 0) { Остановить "не удалось собрать pthread_win.o (нужен clang)" }
}
Copy-Item $Pthread (Join-Path $Папка "lib\sfera\pthread_win.o")

# DLL графики (SDL2, SDL2_ttf и их зависимости) — рядом с панелью.
$Dll = Get-ChildItem -Path (Join-Path $ЛокальнаяСфера "bin") -Filter "*.dll" -ErrorAction SilentlyContinue
if (-not $Dll) { Остановить "в $ЛокальнаяСфера\bin нет DLL SDL2 — сначала запусти установить-windows.ps1" }
$Dll | ForEach-Object { Copy-Item $_.FullName $Папка }

$Читай = @"
Сфера $Версия — панель разработчика для Windows

1. Распакуй архив в любую папку и запусти Sfera-Panel.exe.
2. На вкладке "Обзор" нажми "Установить Сферу" и выбери папку (по умолчанию
   %USERPROFILE%\.sfera). Панель скопирует компилятор и добавит его в PATH.
3. Открой НОВОЕ окно PowerShell и проверь:   запустить --help
   Свой файл:   запустить мой_файл.код

Для сборки программ нужен clang (LLVM): https://github.com/llvm/llvm-project/releases
Исходный код и документация: https://github.com/nikitosklim/Sfera
"@
[System.IO.File]::WriteAllText((Join-Path $Папка "ЧИТАЙ_МЕНЯ.txt"), $Читай, (New-Object System.Text.UTF8Encoding($true)))

Write-Host "4/5  Упаковываю в zip..." -ForegroundColor Cyan
$Архив = Join-Path $Выход "Sfera-Panel-Windows.zip"
if (Test-Path $Архив) { Remove-Item -Force $Архив }
# tar.exe (встроен в Windows 10+) пишет имена файлов в UTF-8 — русские имена
# запустить.exe / сфера_пакеты.exe не превратятся в кракозябры. Compress-
# Archive из PowerShell 5.1 так не умеет.
& tar.exe -a -c -f $Архив -C $Выход "Sfera-Panel-Windows"
if ($LASTEXITCODE -ne 0) { Остановить "tar.exe завершился с кодом $LASTEXITCODE" }

$Размер = [math]::Round((Get-Item $Архив).Length / 1MB, 1)
Write-Host "5/5  Готово: $Архив ($Размер МБ)" -ForegroundColor Green
Write-Host ""
Write-Host "Опубликовать релиз:"
Write-Host "  1) https://github.com/nikitosklim/Sfera/releases/new"
Write-Host "  2) Tag: v$Версия   Title: Сфера $Версия"
Write-Host "  3) Перетащи $Архив в поле Attach binaries, нажми Publish release"
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "Или командой (GitHub CLI):"
    Write-Host "  gh release create v$Версия `"$Архив`" --title `"Сфера $Версия`" --notes `"Панель разработчика для Windows`""
}
