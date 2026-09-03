from __future__ import annotations

import json
import unittest
from pathlib import Path

from be7000_wifi7_lab import scenarios


ROOT = Path(__file__).resolve().parents[1]


class TransactionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.profile = json.loads(
            (ROOT / "profiles/be7000-rc06-qwrt-r26.02.02.json").read_text(encoding="utf-8")
        )
        cls.result = scenarios(cls.profile)

    def test_no_uart_is_blocked_without_writes(self) -> None:
        case = self.result["cases"]["no_uart"]
        self.assertEqual(case["result"], "blocked")
        self.assertEqual(case["events"], ["snapshot-created", "no-write"])

    def test_unverified_gpio_is_blocked_without_writes(self) -> None:
        case = self.result["cases"]["unverified_gpio"]
        self.assertEqual(case["result"], "blocked")
        self.assertEqual(case["state"], self.result["baseline"])

    def test_wrong_caldata_rolls_back(self) -> None:
        case = self.result["cases"]["wrong_caldata"]
        self.assertEqual(case["result"], "rolled-back")
        self.assertEqual(case["state"], self.result["baseline"])

    def test_health_failure_restores_single_phy_state(self) -> None:
        case = self.result["cases"]["health_failure"]
        self.assertEqual(case["result"], "rolled-back")
        self.assertEqual(case["state"]["gpio_453"], 0)
        self.assertEqual(case["state"]["gpio_454"], 1)
        self.assertEqual(case["state"]["caldata_offset"], 413696)
        self.assertEqual(case["state"]["phy_count"], 2)

    def test_mocked_success_uses_exact_split_state(self) -> None:
        state = self.result["cases"]["fully_mocked_success"]["state"]
        self.assertEqual(state["bdf_pci2"], "0x1008")
        self.assertEqual(state["enable_mlo_support"], 1)
        self.assertEqual(state["mlo_chip_bitmask"], 2)
        self.assertEqual(state["gpio_453"], 1)
        self.assertEqual(state["gpio_454"], 0)
        self.assertEqual(state["caldata_offset"], 208896)
        self.assertEqual(state["phy_count"], 3)
        self.assertEqual(state["mld_links"], 2)

    def test_public_profile_keeps_live_apply_disabled(self) -> None:
        gate = self.profile["hardware_gate"]
        self.assertTrue(gate["uart_1v8_required"])
        self.assertFalse(gate["gpio_electrically_tested_on_qwrt"])
        self.assertFalse(gate["live_apply_allowed"])

    def test_openwrt_helper_has_no_live_mutation_primitives(self) -> None:
        helper = (ROOT / "openwrt-package/files/usr/libexec/be7000-wifi7-lab").read_text(
            encoding="utf-8"
        )
        forbidden = (
            "insmod ",
            "rmmod ",
            "wifi reload",
            "uci set ",
            "fw_setenv",
            "mtd write",
            "/sys/class/gpio/export",
        )
        self.assertFalse(any(token in helper for token in forbidden))
        self.assertIn("apply|enable|commit", helper)
        self.assertIn("intentionally absent", helper)


if __name__ == "__main__":
    unittest.main()
