from __future__ import annotations

import argparse
import json
from pathlib import Path

from .model import scenarios


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the BE7000 Wi-Fi 7 control-flow model")
    parser.add_argument("profile", type=Path)
    args = parser.parse_args()
    profile = json.loads(args.profile.read_text(encoding="utf-8"))
    print(json.dumps(scenarios(profile), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
