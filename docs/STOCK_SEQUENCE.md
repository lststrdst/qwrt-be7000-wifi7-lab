# Заводская split-последовательность для NETSCOPE Wi‑Fi 7 Lab

Здесь записаны факты, полученные при локальном разборе прошивки Xiaomi BE7000
RC06. Проприетарные файлы и калибровка устройства не публикуются.

## Логика перехода

Заводская прошивка раздельно управляет сохранённым split state, UCI-топологией
радио, GPIO, выбором калибровки и аргументами CNSS.

### Split: три PHY

```text
GPIO 453 = 1
GPIO 454 = 0
ART calibration offset = 208896 (0x33000)
Calibration length = 184320 bytes
bdf_pci2 = 0x1008
enable_mlo_support = 1
mlo_chip_bitmask = 2
hw_mode_id_soc1 = 5
wifi2 = enabled
hostap MLD = 5g + 5gh
```

### Single-PHY: рабочий откат

```text
GPIO 453 = 0
GPIO 454 = 1
ART calibration offset = 413696 (0x65000)
Calibration length = 184320 bytes
bdf_pci2 = 0x2
enable_mlo_support = 0
wifi2 = disabled
```

Перед переключением сток останавливает Wi-Fi и компоненты CNSS, меняет
аппаратное состояние и обычно перезагружает роутер. Это boot-critical переход,
а не безопасная настройка через `wifi reload`.

Константы подтверждают программный алгоритм Xiaomi. Они не доказывают, что
изменённая загрузка QWRT даст те же GPIO/PCIe timings или что QCN9224 создаст
рабочий EHT beacon.
