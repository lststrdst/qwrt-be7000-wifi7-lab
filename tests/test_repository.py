from __future__ import annotations

import json
import re
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROFILE_PATH = ROOT / "profiles/be7000-rc06-qwrt-r26.02.02.json"
CONF_PATH = ROOT / "openwrt-package/files/etc/be7000-wifi7/profile.conf"


def repository_files() -> list[Path]:
    excluded = {".git", "__pycache__", ".pytest_cache"}
    return [
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and not any(part in excluded or part.endswith(".egg-info") for part in path.parts)
    ]


def shell_assignments(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        result[name] = value.strip("'\"")
    return result


class RepositoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
        cls.conf = shell_assignments(CONF_PATH)

    def test_russian_readme_is_primary_and_links_english(self) -> None:
        russian = (ROOT / "README.md").read_text(encoding="utf-8")
        english = (ROOT / "README.en.md").read_text(encoding="utf-8")
        self.assertIn("## Зачем я это делаю", russian)
        self.assertIn("[English](README.en.md)", russian)
        self.assertIn("[Русский](README.md)", english)
        self.assertIn("## Why I built this", english)

    def test_split_and_rollback_gpio_states_are_inverse(self) -> None:
        split = self.profile["target"]["split_hardware"]
        single = self.profile["target"]["single_hardware"]
        self.assertEqual((split["gpio_453"], split["gpio_454"]), (1, 0))
        self.assertEqual((single["gpio_453"], single["gpio_454"]), (0, 1))

    def test_calibration_windows_are_exact_and_non_overlapping(self) -> None:
        split = self.profile["target"]["split_hardware"]
        single = self.profile["target"]["single_hardware"]
        self.assertEqual(split["caldata_length"], 184320)
        self.assertEqual(single["caldata_length"], 184320)
        split_range = range(split["caldata_offset"], split["caldata_offset"] + split["caldata_length"])
        single_range = range(single["caldata_offset"], single["caldata_offset"] + single["caldata_length"])
        self.assertLessEqual(split_range.stop, single_range.start)

    def test_public_json_and_openwrt_profile_match(self) -> None:
        target = self.profile["target"]
        self.assertEqual(self.conf["TARGET_BDF_PCI2"], target["bdf_pci2"])
        self.assertEqual(int(self.conf["TARGET_ENABLE_MLO_SUPPORT"]), target["enable_mlo_support"])
        self.assertEqual(int(self.conf["TARGET_MLO_CHIP_BITMASK"]), target["mlo_chip_bitmask"])
        self.assertEqual(int(self.conf["TARGET_HW_MODE_ID_SOC1"]), target["hw_mode_id_soc1"])
        self.assertEqual(int(self.conf["TARGET_SPLIT_CALDATA_OFFSET"]), target["split_hardware"]["caldata_offset"])
        self.assertEqual(int(self.conf["TARGET_SINGLE_CALDATA_OFFSET"]), target["single_hardware"]["caldata_offset"])

    def test_repository_has_no_vendor_or_device_artifacts(self) -> None:
        forbidden = {".bin", ".ubi", ".img", ".ipk", ".rar", ".zip", ".gz", ".key", ".pem"}
        offenders = [str(path.relative_to(ROOT)) for path in repository_files() if path.suffix.lower() in forbidden]
        self.assertEqual(offenders, [])

    def test_repository_has_no_local_identity_or_secret_material(self) -> None:
        private_pattern = re.compile(
            r"BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY|PrivateKey\s*=|"
            r"PresharedKey\s*=|sae_password|C:\\Users\\|"
            r"192\.168\.10\.219|24:4B:FE:CB:16:9E",
            re.IGNORECASE,
        )
        offenders = []
        for path in repository_files():
            if path == Path(__file__).resolve():
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            if private_pattern.search(text):
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [])

    def test_openwrt_package_has_no_autostart_hooks(self) -> None:
        package_files = [str(path.relative_to(ROOT / "openwrt-package")) for path in (ROOT / "openwrt-package").rglob("*") if path.is_file()]
        self.assertFalse(any("init.d" in path or "postinst" in path for path in package_files))

    def test_ci_uses_read_only_permissions_and_runs_shell_check(self) -> None:
        workflow = (ROOT / ".github/workflows/tests.yml").read_text(encoding="utf-8")
        self.assertIn("permissions:\n  contents: read", workflow)
        self.assertIn("python -m unittest discover -s tests -v", workflow)
        self.assertIn("sh -n openwrt-package/files/usr/libexec/be7000-wifi7-lab", workflow)

    def test_documented_cli_emits_valid_scenario_report(self) -> None:
        completed = subprocess.run(
            [sys.executable, "-m", "be7000_wifi7_lab", str(PROFILE_PATH)],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        report = json.loads(completed.stdout)
        self.assertEqual(report["cases"]["no_uart"]["result"], "blocked")
        self.assertEqual(report["cases"]["health_failure"]["result"], "rolled-back")
        self.assertEqual(report["cases"]["fully_mocked_success"]["state"]["phy_count"], 3)


if __name__ == "__main__":
    unittest.main()
