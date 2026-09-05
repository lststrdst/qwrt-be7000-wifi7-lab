# Состояние и roadmap NETSCOPE

## Опубликовано и проверяется CI

- исходник LuCI-приложения VPN Quick setup;
- транзакционный runtime обычного WireGuard с подтверждением и watchdog;
- prepare-only drafts для AmneziaWG, VLESS/Xray и Mieru;
- read-only IoT monitor с кольцевыми журналами на USB;
- модели Wi‑Fi 7/MLO и негативные recovery tests;
- render-only пакет `netscope-wifi7-lab`;
- обезличенные VPN-примеры, recovery и SSH/XMiR документация;
- проверка публичного дерева на секреты и vendor/device artifacts.

## Работает на тестовом роутере, но ещё не упаковано здесь

- английская оболочка и вход NETSCOPE;
- встроенная страница Traffic/Devices на основе conntrack;
- ранний Packet Lab и управление локальными capture-сессиями;
- отображение версии `NETSCOPE (QWRT base)` в LuCI.

До публикации соответствующих пакетов эти функции не считаются частью
воспроизводимого релиза.

## Ближайшие задачи

1. Перенести тему/навигацию в `luci-theme-netscope` без изменения штатных
   LuCI routes.
2. Перенести Traffic и Packet Lab в отдельный `luci-app-netscope` с backend,
   лимитами USB и fail-safe recovery.
3. Добавить интеграционные тесты API, nftables/iptables cleanup и USB failure.
4. Доделать отдельные runtime-контракты AWG и VLESS/Xray; Mieru оставить
   disabled, пока нет серверного профиля и health checks.
5. Закрепить воспроизводимую базу сборки, toolchain и package manifest.
6. Проверить чистый first boot, обновление и возврат на известную рабочую
   сборку на отдельном стенде.

## Wi‑Fi 7 / MLO

Текущий этап — только модели и тесты. До UART и аппаратного стенда запрещены:

- live GPIO/CNSS/BDF изменения;
- UCI commit, autostart, bootargs и bootenv;
- запись ART, MIBIB или других разделов;
- публикация переключателя, который выглядит как рабочая функция.

Следующий допустимый этап после появления UART — сбор baseline evidence и
проверка recovery без включения MLO. Только затем возможен одноразовый
RAM-only trial с локальным доступом к питанию.

## Критерии первого образа

Первый публичный image должен иметь:

- закреплённую базу и SHA-256 toolchain/source archives;
- manifest пакетов и лицензий;
- чистый first boot без чужих паролей, host keys, VPN keys и CA;
- рабочие WAN, LAN, DNS, DHCP, Wi‑Fi, LuCI и firewall по умолчанию;
- Capture, MITM, VPN и MLO в состоянии OFF;
- независимый backup/restore и проверенный alternate slot;
- тесты power loss, заполнения USB и удаления USB;
- инструкции stock → NETSCOPE, QWRT → NETSCOPE и NETSCOPE → NETSCOPE;
- release notes с честным списком работающих и экспериментальных функций.
