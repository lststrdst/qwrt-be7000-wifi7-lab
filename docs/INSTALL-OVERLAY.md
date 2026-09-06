# Установка NETSCOPE overlay на Xiaomi BE7000

Публичный релиз 0.7-dev — это установочный слой для **точной QWRT R26.2.2**. Он
не является `factory`/`sysupgrade`, не меняет загрузчик, NAND, UBI, ART или
caldata. Установщик проверяет модель и базу, требует USB `/mnt/sda1`, сверяет
SHA-256 и создаёт полный backup заменяемых файлов.

## До начала

- Xiaomi BE7000 уже загружается в QWRT R26.2.2 и доступен по SSH;
- USB смонтирован в `/mnt/sda1` и доступен на запись;
- NETSCOPE Capture и созданные мастером VPN-профили выключены;
- сохранён исходный backup роутера по [инструкции восстановления](RECOVERY.md).

Если SSH ещё нет, сначала выполнить только подготовительную часть
[гайда XMiR-Patcher](INSTALL-SSH-XMIR.md). Не использовать `sysupgrade -F`.

## Сборка из исходников

```sh
python tools/build_overlay.py
```

В `dist/` появятся архив и отдельный файл SHA-256. Архив содержит только файлы
из `firmware/packages/*/files`, читаемый `manifest.json` и установщик.

## Передача и установка

Распаковать архив на компьютере, скопировать каталог `netscope-overlay` на USB
или в `/tmp` роутера и выполнить из его каталога:

```sh
sha256sum -c SHA256SUMS
sh install.sh
```

На старом Dropbear может понадобиться legacy SCP (`scp -O`). Не передавать в
командной строке пароль роутера или VPN-секреты.

Успешная установка выводит путь вида:

```text
/mnt/sda1/NETSCOPE/backups/overlay.ABCDEF
```

После установки Capture остаётся `OFF`, Docker/MITM не запускается, VPN не
включается. Меняется только тема/язык LuCI и устанавливаются файлы NETSCOPE.
Страница мастера: `/cgi-bin/luci/admin/services/netscope_setup`.

## Откат

Использовать тот же проверенный каталог релиза и выведенный путь backup:

```sh
sh install.sh rollback /mnt/sda1/NETSCOPE/backups/overlay.ABCDEF
```

Rollback останавливает только NETSCOPE Capture, восстанавливает прежние файлы
и LuCI config, удаляет только файлы, которых до установки не существовало.
Network/firewall/VPN не перезапускаются.

## Что не входит

- бинарная база QWRT и vendor firmware;
- `tcpdump`, Xray, AmneziaWG, Mieru и Hysteria 2 для систем, где их нет;
- Docker ARM64 runtime и закреплённый образ mitmproxy;
- ключи, подписки, CA, backup, MAC-адреса и конфигурация владельца.

Quick Setup показывает отсутствие конкретного runtime и не предлагает считать
такой профиль активным. HTTPS lab остаётся недоступен, пока администратор явно
не установит его runtime и не создаст уникальный CA на своём устройстве.
