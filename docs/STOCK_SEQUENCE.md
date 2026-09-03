# Recovered stock split sequence

This document records facts derived from a locally examined Xiaomi BE7000 RC06
firmware image. It does not include or redistribute the vendor files.

## Relevant control flow

The stock firmware has separate layers for persistent split state, wireless
UCI topology, GPIO/calibration switching and CNSS driver arguments.

### Split mode

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

### Single-PHY rollback

```text
GPIO 453 = 0
GPIO 454 = 1
ART calibration offset = 413696 (0x65000)
Calibration length = 184320 bytes
bdf_pci2 = 0x2
enable_mlo_support = 0
wifi2 = disabled
```

The stock transition stops wireless/CNSS components before switching the
hardware state and normally reboots after applying it. That makes this a boot-
critical transition, not a safe `wifi reload` tweak.

These constants are exact software evidence. They do not prove that an altered
QWRT boot path supplies the same GPIO/PCIe timing or that the QCN9224 will
produce a valid EHT beacon.
