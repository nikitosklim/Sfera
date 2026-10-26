# Создаёт admin-token.txt — пароль для загрузки файлов через /admin. Хранить в секрете.
$файл = Join-Path $PSScriptRoot "admin-token.txt"
if (Test-Path $файл) { Write-Host "admin-token.txt уже есть (удалите его, чтобы выпустить новый токен)"; exit 1 }
$байты = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($байты)
$токен = -join ($байты | ForEach-Object { $_.ToString('x2') })
[IO.File]::WriteAllText($файл, $токен)
Write-Host "Токен создан: $токен"
