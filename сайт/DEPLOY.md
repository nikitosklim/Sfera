# Выкладка сайта на сервер

Нужен Linux-сервер (VPS) с доменом. Ниже — вариант с systemd и Caddy (HTTPS получается сам).

## 1. Собрать компилятор и сайт

```
git clone https://github.com/nikitosklim/Sfera
cd Sfera && cargo build --release
cd сайт
../target/release/запустить сервер.код --только-собрать     # получится ./сервер
```

(Для сборки нужны Rust и LLVM 18 — как в README проекта. Либо соберите на своей машине
Linux и скопируйте на сервер папку `сайт/` вместе с бинарником `сервер`.)

## 2. Запуск сервисом (systemd)

Файл `/etc/systemd/system/sfera-site.service`:

```
[Unit]
Description=Сайт языка Сфера
After=network.target

[Service]
WorkingDirectory=/opt/sfera/сайт
ExecStart=/opt/sfera/сайт/сервер 8080
Restart=always
RestartSec=2
# Сервер течёт по ~1 КБ на запрос — раз в сутки перезапускаем для чистоты.
RuntimeMaxSec=86400
User=sfera

[Install]
WantedBy=multi-user.target
```

```
sudo useradd -r -m sfera
sudo chown -R sfera /opt/sfera/сайт
sudo systemctl enable --now sfera-site
```

Рабочая папка обязательно `сайт/` — все пути в программе относительные.

## 3. HTTPS и домен (Caddy)

`/etc/caddy/Caddyfile`:

```
sfera.example.ru {
    reverse_proxy localhost:8080
}
```

Вариант с nginx:

```
server {
    server_name sfera.example.ru;
    client_max_body_size 2g;          # загрузка установщиков через /admin
    proxy_request_buffering off;
    proxy_read_timeout 600s;
    location / { proxy_pass http://127.0.0.1:8080; proxy_set_header Host $host; proxy_buffering off; }
}
```
(сертификат — через `certbot --nginx`). `proxy_buffering off` нужен, чтобы большие установщики
не копились в памяти nginx.

## 4. Токен для загрузки файлов

```
./make-token.sh          # Windows: .\make-token.ps1
```
Создаст `admin-token.txt` (в git не попадает). Откройте `https://ваш-домен/admin`, введите токен,
выберите файл — он попадёт на страницу «Загрузки» с SHA-256. Без `admin-token.txt` загрузка выключена.
Загружайте только по HTTPS (иначе токен виден в сети). Лимит — 2 ГБ, имя файла — латиницей.
Из командной строки: `curl -X PUT -H "Authorization: Bearer $(cat admin-token.txt)" -T файл.zip https://домен/upload/файл.zip`.
Файл с уже существующим именем не перезаписывается — добавляйте версию в имя.

## 5. Новые файлы и статьи

- Установщик: `./add-download.sh файл "Название" "Описание"` — скопирует в `downloads/` и допишет
  строку со SHA-256 в `downloads/list.txt`. Перезапуск не нужен.
- Статья: положите `имя.md` в `content/articles/` и добавьте строку `имя | Название | Описание`
  в `content/articles/list.txt`. Документация — так же, в `content/docs/`.
- Справочник языка — копия `ДОКУМЕНТАЦИЯ_ЯЗЫКА.md`; обновить: `cp ../ДОКУМЕНТАЦИЯ_ЯЗЫКА.md content/docs/language.md`.

## 6. Безопасность

- Запросы записываются в `access.log` (время, метод, адрес).
- Сервер принимает GET/HEAD и PUT на `/upload/` (только с токеном), пути проверяются на `..`, скачать можно только файлы из `list.txt`.
- Наружу открывайте только 80/443 (Caddy/nginx), порт 8080 держите закрытым файрволом.
