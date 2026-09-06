# NETSCOPE

**Проект домашней прошивки для Xiaomi BE7000 на базе QWRT**

**Русский** | [English](README.en.md)

[![NETSCOPE verification](https://github.com/lststrdst/netscope-firmware/actions/workflows/tests.yml/badge.svg)](https://github.com/lststrdst/netscope-firmware/actions/workflows/tests.yml)

Я развиваю NETSCOPE как единый программный слой для своего Xiaomi BE7000
(RC06): русская веб-панель, наблюдение за сетью, безопасная настройка VPN,
восстановление, диагностика IoT и отдельная лаборатория Wi‑Fi 7/MLO.

Основа проекта — QWRT R26.02.02 / QSDK 12.5. Происхождение базы всегда
показывается как `Based on QWRT`; авторство и лицензии исходных компонентов
сохраняются. NETSCOPE не является официальным проектом QWRT, Xiaomi,
Qualcomm или OpenWrt.

> NETSCOPE 0.7-dev выпускается как проверяемый установочный overlay для точной базы
> QWRT R26.2.2: он ставит интерфейс и сервисы поверх работающего роутера, делает
> резервную копию и не пишет NAND/UBI. Это ещё не factory/sysupgrade image — в
> открытом доступе нет соответствующего полного дерева QWRT и toolchain.

## Зачем я это делаю

BE7000 является моим основным домашним шлюзом. Через него проходят обычный
интернет, удалённый доступ, IoT, выборочная маршрутизация и офисный туннель.
Мне нужен не набор разрозненных скриптов, а понятный продукт, где:

- текущее состояние сети видно в одном интерфейсе;
- WireGuard, AmneziaWG, VLESS/Xray, Mieru и Hysteria 2 настраиваются через проверяемый
  мастер, а не случайными командами из истории shell;
- каждая сетевая операция имеет preflight, собственный scope и откат;
- журналы и PCAP-сессии управляются явно и не заполняют внутреннюю flash;
- IoT можно держать в стабильном сегменте, не ломая локальное управление;
- эксперимент с Wi‑Fi 7 невозможно случайно закрепить в загрузке;
- администратор понимает, как вернуться к известному рабочему состоянию.

## Что представляет собой NETSCOPE

| Подсистема | Зачем она нужна | Текущий статус |
|---|---|---|
| NETSCOPE UI | единая русская оболочка LuCI, вход, навигация и версия базы | исходники опубликованы в `luci-theme-netscope`; работает на тестовом роутере |
| NETSCOPE Traffic | устройства, conntrack, направления, порты, счётчики и управляемые USB PCAP-сессии | исходники опубликованы в `luci-app-netscope`; Capture после установки выключен |
| VPN Quick setup | подготовка и явное включение WG, AWG, VLESS/Xray, Mieru и HY2 из вебки | импорт одной Mieru-ссылки без сохранения URI; Telegram/Discord UDP идёт через HY2 с прогретым Mieru-резервом, opt-in автозапуском и fail-open |
| Voice health | текущие Telegram/Discord endpoint, маршрут, задержка, jitter, потери проб и история | метаданные и bounded-журнал на USB; payload звонка не записывается |
| L2TP watchdog | контроль PPP, офисных маршрутов, MTU/MSS и ограниченное переподключение | универсальный сервис опубликован выключенным; приватный probe/routes/reconnect остаётся только на роутере |
| IoT monitor | доказательства потери Wi‑Fi, DHCP, DNS, WAN или облака | опубликован read-only инструмент |
| Recovery | бэкапы, известный baseline и порядок возврата | инструкция опубликована; образ восстановления не распространяется |
| Wi‑Fi 7 / MLO Lab | исследование заводской схемы 5G low + 5G high | только модели, render-only helper и тесты; live apply отсутствует |

Обозначения статуса здесь буквальные:

- **работает** — проверено на моём тестовом роутере;
- **опубликовано** — исходники находятся в этом репозитории;
- **модель** — проверяется только логика и отказоустойчивость, не RF-железо;
- **план** — интерфейс или контракт подготовлен, runtime ещё не выпущен.

Как пользоваться новым мастером: [Быстрая настройка VPN](docs/EASY-SETUP.md).
Три сценария помогают выбрать форму, а запуск по-прежнему требует проверки
и явного подтверждения. Технические параметры доступны в раскрывающихся блоках.

## Почему IoT вынесен отдельно

Голосовая колонка периодически сообщала об отсутствии интернета, хотя WAN
роутера оставался доступен. Позже в тот же диагностический сегмент был добавлен
пылесос. Поэтому для таких клиентов используется отдельная сеть 2,4 ГГц, а из
основной LAN разрешается только необходимое локальное управление.

У штатной прошивки Xiaomi есть Wi‑Fi 7/MLO, но её поддерживаемая конфигурация
не позволяет одновременно оставить два 5‑ГГц радиолинка в одном MLD и вынести
2,4 ГГц в отдельный IoT SSID. Через штатный интерфейс приходится выбирать:
единая MLO-сеть либо разделение диапазонов с потерей нужной MLO-топологии.
Именно это ограничение, а не отсутствие Wi‑Fi 7 на стоке, стало причиной
отдельного IoT-направления в NETSCOPE.

Я не считаю MLO доказанной причиной сбоев колонки. Возможны band steering,
особенности конкретного клиента, DHCP/DNS или облачный сервис. Поэтому
[IoT monitor](tools/netscope-iot-monitor) собирает факты, а
[архитектура сегмента](docs/IOT-NETWORK.md) отделена от MLO-экспериментов.

## Wi‑Fi 7 / MLO без завышенных обещаний

Заводская Xiaomi умеет представить внешний QCN9224 как два 5‑ГГц PHY и
объединить их в MLD. Текущая загрузка QWRT использует single-PHY режим. Для
воспроизведения заводской схемы нужны согласованные GPIO, BDF, ART offset,
параметры CNSS, порядок запуска драйвера и корректная MLO-конфигурация.

В репозитории есть два уровня моделирования:

1. Аппаратная транзакция, для которой обязательны UART 1,8 В и проверка GPIO.
2. Теоретический no-UART trial: только после загрузки, только в RAM, без UCI,
   autostart, bootenv, MTD и ART; после cold boot всегда ожидается исходный
   single-PHY baseline.

Обе модели выполняют **ноль команд на роутере**. Даже успешный сценарий имеет
`live_apply_allowed=false`. Kernel hang отдельно отмечается как состояние,
где программный watchdog не поможет и нужен локальный power cycle.

Технические детали и критерии будущего аппаратного теста находятся в
[Wi‑Fi 7 / MLO Lab](docs/WIFI7-MLO.md). Макет интерфейса —
[в Figma](https://www.figma.com/design/SlXSi90WevQOkB78HuLdFp?node-id=56-318).

## Структура проекта

```text
firmware/
  overlay/                            безопасный установщик поверх QWRT R26.2.2
  packages/luci-app-netscope/         Traffic, PCAP и опциональный HTTPS lab
  packages/luci-theme-netscope/       русская оболочка LuCI
  packages/luci-app-netscope-setup/   VPN Quick setup для LuCI
  packages/netscope-wifi7-lab/        read-only Wi-Fi 7 preflight/renderer
  profiles/                            профиль целевой базы и release gates
src/netscope_firmware/                 офлайн-модели транзакций и recovery
profiles/                              публичные константы целевой платы
tools/netscope-iot-monitor/            read-only диагностика IoT
examples/                              обезличенные шаблоны VPN
docs/                                  архитектура, установка, recovery и labs
tests/                                 product, security и failure-path tests
```

Подробно назначение слоёв описано в [архитектуре NETSCOPE](docs/ARCHITECTURE.md),
а условия первого полноценного flashable-образа — в
[release checklist](firmware/RELEASE-CHECKLIST.md).

Отдельно: [голосовой маршрут и телеметрия](docs/DISCORD-VOICE.md) и
[безопасный L2TP watchdog](docs/L2TP-WATCHDOG.md).

## Локальная проверка

```bash
python -m pip install -e .
python -m unittest discover -s tests -v
python -m netscope_firmware profiles/be7000-rc06-qwrt-r26.02.02.json
python tools/check_public.py
```

CI повторяет тесты на Python 3.10, 3.12 и 3.13, проверяет JavaScript и синтаксис
публичных shell-скриптов. Тесты доказывают свойства кода и recovery-модели, но
не эмулируют QCN9224, PCIe power sequencing, RF, EHT beacon или реальную
multi-link association клиента.

## Установка и выпуск

- [Установка overlay NETSCOPE](docs/INSTALL-OVERLAY.md) — публичный путь без
  записи разделов прошивки, с SHA-256, автоматическим backup и rollback.
- [SSH через XMiR-Patcher](docs/INSTALL-SSH-XMIR.md) описывает подготовку
  доступа, а не обещает универсальную прошивку.
- [firmware/README.md](firmware/README.md) объясняет, как компоненты должны
  попасть в воспроизводимый образ.
- [RECOVERY.md](docs/RECOVERY.md) фиксирует безопасный порядок восстановления.
- [SECURITY.md](SECURITY.md) перечисляет данные, которые нельзя публиковать.

Публичный overlay собирается командой `python tools/build_overlay.py` только из
файлов этого репозитория. Первый полноценный flashable image появится после
закрепления исходной базы и toolchain,
проверки NAND/UBI layout, чистого first boot, резервного слота, power-loss
сценариев и возврата на известную рабочую сборку. `sysupgrade -F`, запись ART
или перенос caldata с другого роутера не используются как обход этих gates.

## Границы проекта

- В Git нет паролей, VPN-подписок, приватных ключей, MAC-адресов и живых backup.
- В Git нет ART, EEPROM, BDF конкретного устройства и vendor firmware blobs.
- MIT-лицензия относится только к моему коду и документации.
- QWRT, OpenWrt, LuCI, Xiaomi и Qualcomm сохраняют собственные лицензии и
  авторство.

## Ссылки

- [Архитектура](docs/ARCHITECTURE.md)
- [Текущее состояние и roadmap](docs/ROADMAP.md)
- [Диагностика Discord Voice и HY2 A/B](docs/DISCORD-VOICE.md)
- [Аудит меню, переводов и элементов LuCI](docs/LUCI-AUDIT.md)
- [История изменений](CHANGELOG.md)
- [OpenWrt Xiaomi BE7000 support work](https://github.com/openwrt/openwrt/pull/20604)
- [Репозиторий NETSCOPE](https://github.com/lststrdst/netscope-firmware)

---

© lststrdst
