from __future__ import annotations

import json
import unittest
from pathlib import Path

from netscope_firmware import RuntimeTrialPolicy, no_uart_scenarios, simulate_no_uart_trial


ROOT = Path(__file__).resolve().parents[1]


class NoUartRuntimeTrialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.profile = json.loads(
            (ROOT / "profiles/be7000-rc06-qwrt-r26.02.02.json").read_text(encoding="utf-8")
        )
        cls.matrix = no_uart_scenarios(cls.profile)

    def test_model_never_authorizes_live_apply(self) -> None:
        results = [self.matrix["success"]]
        results += list(self.matrix["failures"].values())
        results += list(self.matrix["blocked"].values())
        self.assertTrue(all(case["live_apply_allowed"] is False for case in results))

    def test_success_is_runtime_only_and_never_committed(self) -> None:
        case = self.matrix["success"]
        self.assertEqual(case["result"], "trial-active-not-committed")
        self.assertEqual(case["plan"]["candidate_scope"], "post-boot RAM only")
        self.assertEqual(case["plan"]["persistence"], "forbidden")
        self.assertNotIn("committed", " ".join(case["events"]))

    def test_every_software_failure_rolls_back(self) -> None:
        for point in (
            "driver-init",
            "third-phy",
            "mld-create",
            "lan-health",
            "wan-health",
            "confirm-timeout",
        ):
            with self.subTest(point=point):
                case = self.matrix["failures"][point]
                self.assertEqual(case["result"], "rolled-back-in-model")
                self.assertIn("baseline-restored", case["events"])

    def test_kernel_hang_requires_physical_power_cycle(self) -> None:
        case = self.matrix["failures"]["kernel-hang"]
        self.assertEqual(case["result"], "power-cycle-required")
        self.assertIn("cold-boot-baseline-expected", case["events"])

    def test_reboot_discards_unconfirmed_candidate(self) -> None:
        case = self.matrix["failures"]["reboot-before-confirm"]
        self.assertEqual(case["result"], "cold-boot-baseline")
        self.assertFalse(case["policy"]["persistent_writes"])
        self.assertFalse(case["policy"]["autostart_installed"])

    def test_each_persistence_or_recovery_violation_blocks_before_mutation(self) -> None:
        expected = {
            "persistent-write",
            "boot-file-change",
            "uboot-change",
            "art-write",
            "uci-commit",
            "autostart",
            "no-wired-management",
            "no-local-power-cycle",
            "wrong-vendor-tuple",
            "baseline-drift",
        }
        self.assertEqual(set(self.matrix["blocked"]), expected)
        for name, case in self.matrix["blocked"].items():
            with self.subTest(name=name):
                self.assertEqual(case["result"], "blocked")
                self.assertEqual(case["events"][-1], "no-mutation")

    def test_unknown_failure_point_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            simulate_no_uart_trial(self.profile, failure_at="invented")

    def test_missing_local_power_cycle_is_not_accepted(self) -> None:
        case = simulate_no_uart_trial(
            self.profile,
            policy=RuntimeTrialPolicy(local_power_cycle_available=False),
        )
        self.assertEqual(case["result"], "blocked")
        self.assertIn("local_power_cycle_available", case["violations"])


if __name__ == "__main__":
    unittest.main()
