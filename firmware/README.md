# Компоненты прошивки NETSCOPE

Этот каталог содержит пакеты и профиль NETSCOPE для Xiaomi BE7000. Из них
собирается публичный installable overlay для точной QWRT R26.2.2. Он не является
ImageBuilder/SDK tree и не выдаётся за flashable factory/sysupgrade image.

## Зачем нужен отдельный каталог

Я отделяю код, который должен попасть на роутер, от офлайн-моделей, примеров и
документации. Это позволяет заранее проверить состав пакета, публичные файлы и
границы runtime, не смешивая их с живой конфигурацией устройства.

## Состав

### `packages/luci-app-netscope`

NETSCOPE Traffic/Devices, bounded USB PCAP, metadata decoder и опциональный
контроллер HTTPS lab. Capture после установки остаётся выключен. При аварии
сначала удаляются только NETSCOPE redirects, затем останавливаются его процессы.

### `packages/luci-theme-netscope`

Русская оболочка LuCI для Xiaomi BE7000: вход, навигация, версия NETSCOPE и
атрибуция QWRT, встроенный Traffic, быстрые разделы и штатное сохранение пароля.

### `packages/luci-app-netscope-setup`

LuCI-приложение **VPN Quick setup**:

- создаёт уникальные приватные drafts для WireGuard/AmneziaWG;
- валидирует VLESS/Xray и подготавливает Mieru/Hysteria 2;
- проверяет занятые порты и пересечения подсетей;
- хранит приватные файлы с `0700/0600`;
- не пишет секреты в browser storage;
- не меняет UCI и default route;
- для WG/AWG использует отдельные интерфейсы и именованные rules;
- для VLESS/Mieru/Hysteria 2 использует отдельные loopback SOCKS-процессы;
- у каждого runtime есть preflight, подтверждение и watchdog rollback;
- не меняет DNS, default route и policy routing.

### `packages/netscope-wifi7-lab`

Read-only пакет лаборатории Wi‑Fi 7 для Xiaomi BE7000:

- проверяет model/board и наличие ожидаемых QCA/MLO компонентов;
- показывает публичную целевую split-топологию;
- рендерит candidate state только в `/tmp`;
- поддерживает только `status`, `preflight` и `render`;
- блокирует `apply`, `enable` и `commit`;
- не содержит autostart и операций с GPIO, CNSS, UCI, MTD, ART или bootenv.

### `profiles/xiaomi-be7000-qwrt.json`

Manifest целевой базы. `release_state=installable-overlay`, но `flashable=false`:
overlay воспроизводим из опубликованных компонентов, бинарная QWRT-база — нет.

### `overlay/install.sh` и `tools/build_overlay.py`

Детерминированная сборка release archive, проверка target/base, SHA-256,
автоматический USB backup и scoped rollback. Установщик не вызывает `mtd`,
`sysupgrade` и не перезапускает network/firewall/VPN.

## Чего здесь пока нет

- полного исходного дерева QWRT R26.02.02;
- first-boot wizard и генерации уникальных device keys/CA;
- переносимого Docker ARM64 runtime для HTTPS lab;
- policy-routing слоя для подготовленных VLESS/Mieru/Hysteria 2 SOCKS;
- проверенного sysupgrade/factory image.

## Как собрать текущий overlay

```sh
python tools/build_overlay.py
```

Подробная установка: [docs/INSTALL-OVERLAY.md](../docs/INSTALL-OVERLAY.md).

## Как компонент станет частью flashable image

1. Закрепить совместимую базу, toolchain и SHA-256 исходных архивов.
2. Поместить пакет в `package/` этой базы без живых конфигов устройства.
3. Собрать `.ipk` и проверить его в `opkg --offline-root`.
4. Проверить установку/удаление на отдельном стенде.
5. Запустить API, firewall, USB и recovery tests.
6. Собрать полный image из чистого дерева.
7. Пройти [release checklist](RELEASE-CHECKLIST.md) и опубликовать manifest.

Пример сборки одного пакета после получения совместимого SDK:

```sh
make package/luci-app-netscope-setup/compile V=s
make package/netscope-wifi7-lab/compile V=s
```

Это команды сборки пакетов, а не готовой flashable-прошивки. `--force-depends`,
`sysupgrade -F` и запись поверх неизвестной разметки не являются допустимым
способом установки NETSCOPE.

## Лицензии

MIT-лицензия относится только к оригинальному коду NETSCOPE. QWRT, LuCI,
OpenWrt, Xiaomi/Qualcomm binaries и сторонние библиотеки сохраняют собственные
лицензии и атрибуции. Device-specific ART/caldata, ключи и backup в публичную
сборку не включаются.
