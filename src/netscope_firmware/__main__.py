from __future__ import annotations

import argparse
import json
from pathlib import Path

from .model import scenarios
from .runtime_trial import no_uart_scenarios


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="python -m netscope_firmware",
        description="Run NETSCOPE offline safety models for the Xiaomi BE7000 Wi-Fi 7 lab",
    )
    parser.add_argument("profile", type=Path)
    args = parser.parse_args()
    profile = json.loads(args.profile.read_text(encoding="utf-8"))
    report = scenarios(profile)
    report["no_uart_runtime_trial"] = no_uart_scenarios(profile)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
