# Safety model

## Invariants

- Never write ART, MIBIB, bootloader partitions or device calibration data.
- Never test boot-critical changes without a verified 1.8 V UART console.
- Never overwrite the only management radio during the first EHT test.
- Never commit a candidate state before LAN, WAN, AP and watchdog checks pass.
- Never publish configuration backups, VPN material, Wi-Fi credentials,
  device calibration files or vendor firmware blobs.

## Required hardware-stage transaction

1. Verify board identity, firmware fingerprints and device-owned calibration.
2. Snapshot every file and runtime value that the experiment may touch.
3. Arm an out-of-band rollback before stopping any radio service.
4. Stage the split state in RAM first; do not add autostart.
5. Require the third PHY, EHT beacon and management path to become healthy.
6. Create a temporary MLD and associate a compatible Wi-Fi 7 client.
7. Force a health failure and prove automatic single-PHY restoration.
8. Only then consider a cold-boot test and persistent integration.

The current repository implements only the pure model for this transaction.
