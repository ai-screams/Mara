#!/usr/bin/env python3
"""레거시 게시 파이프라인의 XML·버전 판단(legacy-publish.sh가 부른다).

    legacy-feed.py item <appcast.xml>          → "VERSION URL" (단일 항목 피드의 sparkle:version, enclosure url)
    legacy-feed.py max <appcast.xml>           → 피드의 가장 높은 sparkle:version (본판 피드용)
    legacy-feed.py compare <a> <b>             → -1 / 0 / 1
    legacy-feed.py --selftest

버전 비교: 레거시(114.N)와 본판(git 커밋 수 정수) 빌드 번호는 **숫자만으로 된 점 구분 버전**이다. 이 형식에서
Sparkle `SUStandardVersionComparator`는 성분별 숫자 비교이고, 앞이 같으면 성분이 더 많은 쪽이 새것이다
(114 < 114.1, 114.9 < 114.10). 그 의미를 그대로 구현하되, 숫자가 아닌 값은 **거부**한다 — 다른 형식이 들어오면
Sparkle과 결과가 갈릴 수 있으므로 추측하지 않고 실패한다. (publish job에서 Sparkle을 다시 받아 컴파일하지 않으려는 선택)
"""

import re
import sys
import xml.etree.ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
NUMERIC = re.compile(r"^[0-9]+(\.[0-9]+)*$")


def parse_version(v: str) -> tuple:
    v = v.strip()
    if not NUMERIC.match(v):
        sys.exit(f"non-numeric version {v!r} — refusing to guess Sparkle ordering")
    return tuple(int(part) for part in v.split("."))


def compare(a: str, b: str) -> int:
    ta, tb = parse_version(a), parse_version(b)
    return (ta > tb) - (ta < tb)   # 튜플 비교: 앞 성분이 같으면 긴 쪽이 크다(Sparkle과 같다)


def item_version(item) -> str:
    element = item.find(SPARKLE + "version")
    if element is not None and (element.text or "").strip():
        return element.text.strip()
    enclosure = item.find("enclosure")
    value = enclosure.get(SPARKLE + "version") if enclosure is not None else None
    if not value:
        sys.exit("item has no sparkle:version")
    return value.strip()


def items(path: str) -> list:
    found = list(ET.parse(path).getroot().iter("item"))
    if not found:
        sys.exit(f"{path}: no <item>")
    return found


def cmd_item(path: str) -> None:
    found = items(path)
    if len(found) != 1:
        sys.exit(f"{path}: legacy feed must have exactly one item, found {len(found)}")
    enclosure = found[0].find("enclosure")
    print(item_version(found[0]), enclosure.get("url") if enclosure is not None else "")


def cmd_max(path: str) -> None:
    best = None
    for item in items(path):
        v = item_version(item)
        if best is None or compare(v, best) > 0:
            best = v
    print(best)


def selftest() -> None:
    cases = [("114.1", "115", -1), ("114.99", "115", -1), ("114.9", "114.10", -1), ("114", "114.1", -1),
             ("114.3", "114.3", 0), ("123", "114.5", 1), ("115", "114.99", 1)]
    for a, b, want in cases:
        got = compare(a, b)
        assert got == want, f"compare({a},{b})={got}, want {want}"
    for bad in ("1.2.3-beta", "", "v115", "114.a"):
        try:
            compare(bad, "1")
        except SystemExit:
            continue
        raise AssertionError(f"non-numeric {bad!r} accepted")
    print("✅ legacy-feed: selftest passed")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["--selftest"]:
        selftest()
    elif len(args) == 2 and args[0] == "item":
        cmd_item(args[1])
    elif len(args) == 2 and args[0] == "max":
        cmd_max(args[1])
    elif len(args) == 3 and args[0] == "compare":
        print(compare(args[1], args[2]))
    else:
        sys.exit(__doc__)
