# Состояние и roadmap NETSCOPE

## Опубликовано и проверяется CI

- исходник LuCI-приложения VPN Quick setup;
- протокольно-изолированные runtimes WG, AWG, VLESS/Xray, Mieru и Hysteria 2 с
  подтверждением, health check и watchdog rollback;
- русская тема NETSCOPE, Traffic/Devices, USB PCAP и опциональный HTTPS lab;
- воспроизводимый installable overlay для точной QWRT R26.2.2;
- read-only IoT monitor с кольцевыми журналами на USB;
- модели Wi‑Fi 7/MLO и негативные recovery tests;
- render-only пакет `netscope-wifi7-lab`;
- обезличенные VPN-примеры, recovery и SSH/XMiR документация;
- проверка публичного дерева на секреты и vendor/device artifacts.

## Ближайшие задачи

1. Добавить интеграционные тесты API, iptables cleanup и USB failure.
2. Упаковать документированный ARM64 Docker runtime для HTTPS lab без vendor blobs.
3. Добавить policy-routing слой поверх loopback VLESS/Mieru/HY2 с отдельным rollback; первым профилем сделать узкий Discord voice A/B-тест без захвата игр.
4. Проверить AWG, Mieru и Hysteria 2 на реальных внешних серверах; без бинарника их preflight заблокирован.
5. Закрепить воспроизводимую QWRT/OpenWrt базу, toolchain и package manifest.
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
