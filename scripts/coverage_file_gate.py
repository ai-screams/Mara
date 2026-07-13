#!/usr/bin/env python3
"""Fail when a critical source file drops below its line-coverage floor."""

import argparse
import json
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", action="append", default=[], metavar="SUFFIX=PERCENT")
    args = parser.parse_args()
    files = json.load(sys.stdin)["data"][0]["files"]
    percentages = {
        item["filename"]: float(item["summary"]["lines"]["percent"])
        for item in files
    }

    failed = False
    for spec in args.file:
        suffix, raw_floor = spec.rsplit("=", 1)
        floor = float(raw_floor)
        matches = [value for path, value in percentages.items() if path.endswith(suffix)]
        if len(matches) != 1:
            print(f"::error::coverage file gate expected one match for {suffix}, got {len(matches)}")
            failed = True
            continue
        actual = matches[0]
        print(f"Critical coverage: {suffix} {actual:.1f}% (floor {floor:g}%)")
        if actual < floor:
            print(f"::error::{suffix} coverage {actual:.1f}% is below floor {floor:g}%")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
