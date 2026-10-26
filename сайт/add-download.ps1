# Копирует файл в downloads\ и добавляет строку (с SHA-256) в downloads\list.txt.
# Использование: .\add-download.ps1 путь\к\файлу "Название" "Описание"
param([Parameter(Mandatory=$true)][string]$Файл, [string]$Название = "", [string]$Описание = "")
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Файл)) { throw "Файл не найден: $Файл" }
$имя = Split-Path $Файл -Leaf
if ($имя -notmatch '^[A-Za-z0-9._-]+$') { throw "Имя файла только латиницей, цифры . _ -" }
$папка = Join-Path $PSScriptRoot "downloads"
Copy-Item $Файл (Join-Path $папка $имя) -Force
$сумма = (Get-FileHash (Join-Path $папка $имя) -Algorithm SHA256).Hash.ToLower()
if ($Название -eq "") { $Название = $имя }
Add-Content -Path (Join-Path $папка "list.txt") -Value "$имя | $Название | $Описание | $сумма" -Encoding UTF8
Write-Host "Добавлено: $имя ($сумма)"
