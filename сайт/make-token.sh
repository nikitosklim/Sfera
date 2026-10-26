#!/bin/sh
# Создаёт admin-token.txt — пароль для загрузки файлов через /admin. Хранить в секрете.
cd "$(dirname "$0")"
if [ -f admin-token.txt ]; then echo "admin-token.txt уже есть (удалите его, чтобы выпустить новый токен)"; exit 1; fi
(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n') | tr -d '\n' > admin-token.txt
chmod 600 admin-token.txt
echo "Токен создан:"; cat admin-token.txt; echo
