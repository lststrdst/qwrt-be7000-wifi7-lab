from __future__ import annotations

import copy
from dataclasses import asdict, dataclass


@dataclass
class RouterState:
    """Only the control-plane state that can be modeled without RF hardware."""

    bdf_pci2: str = "0x2"
    enable_mlo_support: int = 0
    mlo_chip_bitmask: int = 255
    hw_mode_id_soc1: int = 0
    phy_count: int = 2
    main_mode: str = "HE160"
    main_available: bool = True
    wan_available: bool = True
    mld_links: int = 0
    gpio_453: int = 0
    gpio_454: int = 1
    caldata_offset: int = 413696
    committed: bool = False


def run_transaction(
    baseline: RouterState,
    profile: dict,
    *,
    uart_verified: bool,
    gpio_electrically_verified: bool,
    caldata_matches: bool,
    health_check_passes: bool,
) -> dict:
    """Model one candidate activation. This function performs no I/O."""

    before = copy.deepcopy(baseline)
    state = copy.deepcopy(baseline)
    events = ["snapshot-created"]

    if not uart_verified:
        return _result("blocked", "UART 1.8V is not verified", events + ["no-write"], state)
    if not gpio_electrically_verified:
        return _result(
            "blocked",
            "GPIO electrical behavior is not verified under QWRT",
            events + ["no-write"],
            state,
        )

    target = profile["target"]
    split = target["split_hardware"]
    state.bdf_pci2 = target["bdf_pci2"]
    state.enable_mlo_support = target["enable_mlo_support"]
    state.mlo_chip_bitmask = target["mlo_chip_bitmask"]
    state.hw_mode_id_soc1 = target["hw_mode_id_soc1"]
    state.gpio_453 = split["gpio_453"]
    state.gpio_454 = split["gpio_454"]
    state.caldata_offset = split["caldata_offset"]
    events.append("candidate-staged")

    if not caldata_matches:
        return _result(
            "rolled-back",
            "caldata fingerprint mismatch",
            events + ["driver-start-refused", "snapshot-restored"],
            before,
        )

    state.phy_count = 3
    state.main_mode = "EHT160+EHT80"
    state.mld_links = 2
    events.extend(["stock-split-sequence-modeled", "third-phy-present", "temporary-mld-created"])

    if not health_check_passes:
        return _result(
            "rolled-back",
            "LAN/WAN/AP health check failed",
            events + ["watchdog-triggered", "snapshot-restored"],
            before,
        )

    state.committed = True
    return _result(
        "committed-in-model",
        "all modeled gates passed; hardware is still unproven",
        events + ["candidate-committed-in-model"],
        state,
    )


def scenarios(profile: dict) -> dict:
    baseline = RouterState()
    common = {"baseline": baseline, "profile": profile}
    return {
        "emulation_scope": "control flow, gates and rollback only",
        "not_emulated": [
            "QCN9224 RF",
            "PCIe power sequencing",
            "GPIO electrical state",
            "EHT beacon",
            "client association",
        ],
        "baseline": asdict(baseline),
        "cases": {
            "no_uart": run_transaction(
                **common,
                uart_verified=False,
                gpio_electrically_verified=False,
                caldata_matches=True,
                health_check_passes=True,
            ),
            "unverified_gpio": run_transaction(
                **common,
                uart_verified=True,
                gpio_electrically_verified=False,
                caldata_matches=True,
                health_check_passes=True,
            ),
            "wrong_caldata": run_transaction(
                **common,
                uart_verified=True,
                gpio_electrically_verified=True,
                caldata_matches=False,
                health_check_passes=True,
            ),
            "health_failure": run_transaction(
                **common,
                uart_verified=True,
                gpio_electrically_verified=True,
                caldata_matches=True,
                health_check_passes=False,
            ),
            "fully_mocked_success": run_transaction(
                **common,
                uart_verified=True,
                gpio_electrically_verified=True,
                caldata_matches=True,
                health_check_passes=True,
            ),
        },
    }


def _result(result: str, reason: str, events: list[str], state: RouterState) -> dict:
    return {"result": result, "reason": reason, "events": events, "state": asdict(state)}
