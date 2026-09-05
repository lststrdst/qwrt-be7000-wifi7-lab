# Компоненты прошивки NETSCOPE

Этот каталог содержит пакеты и профиль будущего образа NETSCOPE для Xiaomi
BE7000. Сейчас он не является готовым ImageBuilder/SDK tree и не производит
flashable image.

## Зачем нужен отдельный каталог

Я отделяю код, который должен попасть на роутер, от офлайн-моделей, примеров и
документации. Это позволяет заранее проверить состав пакета, публичные файлы и
границы runtime, не смешивая их с живой конфигурацией устройства.

## Состав

### `packages/luci-app-netscope-setup`

LuCI-приложение **VPN Quick setup**:

- создаёт уникальные приватные drafts для WireGuard/AmneziaWG;
- валидирует VLESS/Xray и подготавливает Mieru-шаблон;
- проверяет занятые порты и пересечения подсетей;
- хранит приватные файлы с `0700/0600`;
- не пишет секреты в browser storage;
- не меняет UCI и default route;
- для plain WireGuard использует отдельный интерфейс, именованные rules,
  подтверждение и watchdog rollback;
- оставляет AWG, VLESS/Xray и Mieru в состоянии prepare-only.

### `packages/netscope-wifi7-lab`

Read-only пакет лаборатории Wi‑Fi 7 для Xiaomi BE7000:

- проверяет model/board и наличие ожидаемых QCA/MLO компонентов;
- показывает публичную целевую split-топологию;
- рендерит candidate state только в `/tmp`;
- поддерживает только `status`, `preflight` и `render`;
- блокирует `apply`, `enable` и `commit`;
- не содержит autostart и операций с GPIO, CNSS, UCI, MTD, ART или bootenv.

### `profiles/xiaomi-be7000-qwrt.json`

Manifest целевой базы. Пока `flashable=false`, а build source/toolchain не
закреплены контрольными суммами. Это предохранитель от публикации архива,
который выглядит как прошивка, но не имеет воспроизводимого происхождения.

## Чего здесь пока нет

- полного исходного дерева QWRT R26.02.02;
- `luci-theme-netscope`;
- публичного пакета NETSCOPE Traffic/Packet Lab;
- runtime AWG/VLESS/Mieru с независимым rollback;
- first-boot wizard и генерации уникальных device keys/CA;
- проверенного sysupgrade/factory image.

## Как компонент станет частью образа

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

Это команды сборки пакетов, а не готовой прошивки. `--force-depends`,
`sysupgrade -F` и запись поверх неизвестной разметки не являются допустимым
способом установки NETSCOPE.

## Лицензии

MIT-лицензия относится только к оригинальному коду NETSCOPE. QWRT, LuCI,
OpenWrt, Xiaomi/Qualcomm binaries и сторонние библиотеки сохраняют собственные
лицензии и атрибуции. Device-specific ART/caldata, ключи и backup в публичную
сборку не включаются.
