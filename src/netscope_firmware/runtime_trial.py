from __future__ import annotations

from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class RuntimeTrialPolicy:
    """Recovery properties for a supervised, post-boot MLO experiment.

    The model never performs I/O.  It describes the narrow class of experiments
    that may be recoverable without UART: all candidate state lives in RAM and a
    cold power cycle returns the unchanged QWRT boot path.
    """

    ephemeral_only: bool = True
    persistent_writes: bool = False
    boot_files_touched: bool = False
    uboot_environment_touched: bool = False
    art_or_caldata_written: bool = False
    uci_committed: bool = False
    autostart_installed: bool = False
    wired_management_verified: bool = True
    local_power_cycle_available: bool = True
    vendor_tuple_matches: bool = True
    baseline_fingerprints_match: bool = True


FAILURE_POINTS = (
    "driver-init",
    "third-phy",
    "mld-create",
    "lan-health",
    "wan-health",
    "confirm-timeout",
    "kernel-hang",
    "reboot-before-confirm",
)


def simulate_no_uart_trial(
    profile: dict,
    *,
    policy: RuntimeTrialPolicy | None = None,
    failure_at: str | None = None,
) -> dict:
    """Model a RAM-only trial and its recovery path without touching hardware."""

    policy = policy or RuntimeTrialPolicy()
    events = ["model-only", "baseline-verified"]
    violations = _policy_violations(policy)
    if failure_at is not None and failure_at not in FAILURE_POINTS:
        raise ValueError(f"unknown failure point: {failure_at}")

    if violations:
        return {
            "result": "blocked",
            "reason": "runtime-only recovery contract is not satisfied",
            "violations": violations,
            "events": events + ["no-mutation"],
            "live_apply_allowed": False,
            "policy": asdict(policy),
        }

    target = profile["target"]
    plan = {
        "candidate_scope": "post-boot RAM only",
        "split_tuple": {
            "bdf_pci2": target["bdf_pci2"],
            "enable_mlo_support": target["enable_mlo_support"],
            "mlo_chip_bitmask": target["mlo_chip_bitmask"],
            "hw_mode_id_soc1": target["hw_mode_id_soc1"],
            "gpio_453": target["split_hardware"]["gpio_453"],
            "gpio_454": target["split_hardware"]["gpio_454"],
            "caldata_offset": target["split_hardware"]["caldata_offset"],
        },
        "rollback_scope": "restore runtime snapshot or cold power cycle",
        "persistence": "forbidden",
        "confirmation": "required before watchdog deadline",
    }
    events += ["ram-overlay-staged", "watchdog-armed", "candidate-modeled"]

    if failure_at == "kernel-hang":
        return _outcome(
            "power-cycle-required",
            "software watchdog cannot run while the kernel is hung",
            events + ["kernel-unresponsive", "cold-boot-baseline-expected"],
            policy,
            plan,
        )
    if failure_at == "reboot-before-confirm":
        return _outcome(
            "cold-boot-baseline",
            "candidate state was volatile and was not installed at boot",
            events + ["power-lost", "cold-boot-baseline-expected"],
            policy,
            plan,
        )
    if failure_at:
        return _outcome(
            "rolled-back-in-model",
            f"health gate failed at {failure_at}",
            events + [f"failure:{failure_at}", "watchdog-rollback", "baseline-restored"],
            policy,
            plan,
        )

    return _outcome(
        "trial-active-not-committed",
        "all modeled runtime gates passed; RF, GPIO and kernel behavior remain unproven",
        events + ["third-phy-modeled", "mld-modeled", "health-gates-modeled"],
        policy,
        plan,
    )


def no_uart_scenarios(profile: dict) -> dict:
    """Return the complete negative-test matrix used by CI."""

    blocked_policies = {
        "persistent-write": RuntimeTrialPolicy(persistent_writes=True),
        "boot-file-change": RuntimeTrialPolicy(boot_files_touched=True),
        "uboot-change": RuntimeTrialPolicy(uboot_environment_touched=True),
        "art-write": RuntimeTrialPolicy(art_or_caldata_written=True),
        "uci-commit": RuntimeTrialPolicy(uci_committed=True),
        "autostart": RuntimeTrialPolicy(autostart_installed=True),
        "no-wired-management": RuntimeTrialPolicy(wired_management_verified=False),
        "no-local-power-cycle": RuntimeTrialPolicy(local_power_cycle_available=False),
        "wrong-vendor-tuple": RuntimeTrialPolicy(vendor_tuple_matches=False),
        "baseline-drift": RuntimeTrialPolicy(baseline_fingerprints_match=False),
    }
    return {
        "scope": "simulation only; no router commands are emitted",
        "guarantee": "recoverability from volatile software state, not electrical safety",
        "residual_risks": [
            "GPIO electrical behavior under QWRT is not verified",
            "CNSS module reload may hang or panic the kernel",
            "a kernel hang requires a local cold power cycle",
            "RF operation, EHT beacons and client MLO association are not emulated",
        ],
        "success": simulate_no_uart_trial(profile),
        "failures": {
            name: simulate_no_uart_trial(profile, failure_at=name)
            for name in FAILURE_POINTS
        },
        "blocked": {
            name: simulate_no_uart_trial(profile, policy=policy)
            for name, policy in blocked_policies.items()
        },
    }


def _policy_violations(policy: RuntimeTrialPolicy) -> list[str]:
    required_true = {
        "ephemeral_only": policy.ephemeral_only,
        "wired_management_verified": policy.wired_management_verified,
        "local_power_cycle_available": policy.local_power_cycle_available,
        "vendor_tuple_matches": policy.vendor_tuple_matches,
        "baseline_fingerprints_match": policy.baseline_fingerprints_match,
    }
    required_false = {
        "persistent_writes": policy.persistent_writes,
        "boot_files_touched": policy.boot_files_touched,
        "uboot_environment_touched": policy.uboot_environment_touched,
        "art_or_caldata_written": policy.art_or_caldata_written,
        "uci_committed": policy.uci_committed,
        "autostart_installed": policy.autostart_installed,
    }
    return [name for name, value in required_true.items() if not value] + [
        name for name, value in required_false.items() if value
    ]


def _outcome(
    result: str,
    reason: str,
    events: list[str],
    policy: RuntimeTrialPolicy,
    plan: dict,
) -> dict:
    return {
        "result": result,
        "reason": reason,
        "events": events,
        "policy": asdict(policy),
        "plan": plan,
        "live_apply_allowed": False,
    }
