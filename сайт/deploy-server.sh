#!/bin/sh
# Выкладка сайта на сервер. Запускать НА СЕРВЕРЕ от root (или через sudo):
#   sh deploy-server.sh sfera-site-linux.tar.gz [порт]
# Первый раз ставит сервис и разворачивает сайт в /opt/sfera, дальше —
# обновляет файлы сайта, не трогая загрузки (downloads/) и токен.
set -e
ARCH="$1"; PORT="${2:-8080}"
[ -f "$ARCH" ] || { echo "Использование: sh deploy-server.sh архив.tar.gz [порт]"; exit 1; }
ARCH=$(cd "$(dirname "$ARCH")" && pwd)/$(basename "$ARCH")
id sfera >/dev/null 2>&1 || useradd -r -m sfera
mkdir -p /opt/sfera
# Сохраняем загрузки и токен при обновлении.
KEEP=/tmp/sfera-keep.$$; mkdir -p "$KEEP"
[ -d /opt/sfera/сайт/downloads ] && cp -a /opt/sfera/сайт/downloads "$KEEP/"
[ -f /opt/sfera/сайт/admin-token.txt ] && cp -a /opt/sfera/сайт/admin-token.txt "$KEEP/"
# Данные сайта (журналы посещений и статистики и т. д.) лежат в данные/.
[ -d /opt/sfera/сайт/данные ] && cp -a /opt/sfera/сайт/данные "$KEEP/"
# Прежние версии писали журналы в корень сайта: переносим их в данные/.
mkdir -p "$KEEP/данные"
for f in visits.log access.log; do
  [ -f /opt/sfera/сайт/$f ] && [ ! -f "$KEEP/данные/$f" ] && cp -a /opt/sfera/сайт/$f "$KEEP/данные/$f"
done
tar -xzf "$ARCH" -C /opt/sfera
[ -d "$KEEP/downloads" ] && cp -a "$KEEP/downloads/." /opt/sfera/сайт/downloads/
[ -f "$KEEP/admin-token.txt" ] && cp -a "$KEEP/admin-token.txt" /opt/sfera/сайт/
mkdir -p /opt/sfera/сайт/данные && cp -a "$KEEP/данные/." /opt/sfera/сайт/данные/
rm -rf "$KEEP"
chmod +x /opt/sfera/сайт/сервер
[ -f /opt/sfera/сайт/admin-token.txt ] || {
  head -c 24 /dev/urandom | base64 | tr -d '/+=\n' > /opt/sfera/сайт/admin-token.txt
  echo "Создан токен загрузки: /opt/sfera/сайт/admin-token.txt"; }
chown -R sfera /opt/sfera/сайт
cat > /etc/systemd/system/sfera-site.service <<EOF
[Unit]
Description=Сайт языка Сфера
After=network.target

[Service]
WorkingDirectory=/opt/sfera/сайт
ExecStart=/opt/sfera/сайт/сервер $PORT
Restart=always
RestartSec=2
RuntimeMaxSec=86400
User=sfera

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sfera-site >/dev/null 2>&1
systemctl restart sfera-site
sleep 1
systemctl --no-pager --lines=5 status sfera-site || true
echo "Проверка: curl -sI http://127.0.0.1:$PORT/ | head -1"
curl -sI "http://127.0.0.1:$PORT/" | head -1 || true
