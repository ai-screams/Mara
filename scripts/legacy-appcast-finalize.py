#!/usr/bin/env python3
"""레거시 appcast 마무리(P3 finalize + P4 검증): generate_appcast가 **후보 DMG 하나만** 넣고 만든 단일 항목 피드에
OS 범위와 릴리스 노트 링크를 넣고, 그 항목이 정말 이번 후보인지 단언한다.

    legacy-appcast-finalize.py <appcast.xml> <owner/repo> <release-tag> <dmg> <short-version> <build>
    legacy-appcast-finalize.py --selftest

- minimumSystemVersion 10.13.0 / maximumSystemVersion 13.99.99(Sparkle 권장 세 자리): 앱의 피드 전환이 어떤 이유로
  실패해도 14+(본판 최소 OS)에서는 레거시 항목이 제안되지 않게 하는 두 번째 방어선. generate_appcast는 새 항목의
  maximumSystemVersion을 넣지 않으므로(Sparkle 2.9.6 `UpdateBranch(… maximumSystemVersion: nil …)`) 여기서 넣는다.
- releaseNotesLink: 업데이트 창에 이 릴리스의 GitHub 페이지를 보인다(본판 release.yml과 같은 방식).
- 삽입은 항목·enclosure가 정확히 하나일 때만 한다(결정적). 이미 있던 세 요소는 지우고 다시 써서 두 번 돌려도 같은
  바이트가 된다. 피드 자체는 서명하지 않으므로(SURequireSignedFeed 없음) 사후 편집이 서명을 깨지 않는다 — DMG의
  EdDSA 서명은 enclosure 속성에 그대로 남는다.
"""

import os
import re
import sys
import tempfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

MINIMUM = "10.13.0"
MAXIMUM = "13.99.99"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
OWN_LINES = re.compile(
    r"^[ \t]*<sparkle:(minimumSystemVersion|maximumSystemVersion|releaseNotesLink)>[^<]*</sparkle:\1>[ \t]*\n",
    re.MULTILINE,
)


def finalize(text: str, notes_link: str) -> str:
    if text.count("<item>") != 1 or text.count("<enclosure ") != 1:
        sys.exit("expected exactly one <item> with one <enclosure> (legacy feed is single-item)")
    text = OWN_LINES.sub("", text)
    inserted = (
        f"<sparkle:minimumSystemVersion>{MINIMUM}</sparkle:minimumSystemVersion>\n"
        f"            <sparkle:maximumSystemVersion>{MAXIMUM}</sparkle:maximumSystemVersion>\n"
        f"            <sparkle:releaseNotesLink>{escape(notes_link)}</sparkle:releaseNotesLink>\n"
        "            <enclosure "
    )
    return text.replace("<enclosure ", inserted, 1)


def verify(text: str, notes_link: str, url: str, length: int, short: str, build: str) -> None:
    items = list(ET.fromstring(text).iter("item"))
    if len(items) != 1:
        sys.exit(f"expected exactly one <item>, found {len(items)}")
    item = items[0]

    def one(tag: str) -> str:
        values = [e.text for e in item.findall(SPARKLE + tag)]
        if len(values) != 1:
            sys.exit(f"{tag}: expected exactly one, found {values}")
        return (values[0] or "").strip()

    # 버전은 enclosure 속성이 아니라 top-level 요소로 나온다(Sparkle 2.x generate_appcast).
    checks = (
        ("minimumSystemVersion", MINIMUM),
        ("maximumSystemVersion", MAXIMUM),
        ("releaseNotesLink", notes_link),
        ("version", build),
        ("shortVersionString", short),
    )
    for tag, expected in checks:
        if one(tag) != expected:
            sys.exit(f"{tag} is {one(tag)!r}, expected {expected!r}")
    enclosure = item.find("enclosure")
    if enclosure is None:
        sys.exit("item has no <enclosure>")
    if enclosure.get("url") != url:
        sys.exit(f"enclosure url {enclosure.get('url')!r}, expected {url!r}")
    if enclosure.get("length") != str(length):
        sys.exit(f"enclosure length {enclosure.get('length')!r}, expected {length}")
    if not (enclosure.get(SPARKLE + "edSignature") or "").strip():
        sys.exit("enclosure has no sparkle:edSignature")


def run(path: str, repo: str, tag: str, dmg: str, short: str, build: str) -> None:
    notes_link = f"https://github.com/{repo}/releases/tag/{tag}"
    url = f"https://github.com/{repo}/releases/download/{tag}/{os.path.basename(dmg)}"
    with open(path, encoding="utf-8") as handle:
        text = finalize(handle.read(), notes_link)
    verify(text, notes_link, url, os.path.getsize(dmg), short, build)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    print(f"appcast finalized: 1 item ({short} / {build}), macOS {MINIMUM}–{MAXIMUM}")


SAMPLE = """<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>Mara</title>
        <item>
            <title>0.11.2</title>
            <sparkle:version>114.3</sparkle:version>
            <sparkle:shortVersionString>0.11.2</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>10.13</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/o/r/releases/download/legacy-v0.11.2-3/Mara-0.11.2-legacy-3.dmg" length="4" type="application/octet-stream" sparkle:edSignature="c2ln"/>
        </item>
    </channel>
</rss>
"""


def selftest() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        dmg = os.path.join(tmp, "Mara-0.11.2-legacy-3.dmg")
        with open(dmg, "wb") as handle:
            handle.write(b"abcd")
        feed = os.path.join(tmp, "appcast.xml")
        with open(feed, "w") as handle:
            handle.write(SAMPLE)
        run(feed, "o/r", "legacy-v0.11.2-3", dmg, "0.11.2", "114.3")
        first = open(feed).read()
        run(feed, "o/r", "legacy-v0.11.2-3", dmg, "0.11.2", "114.3")   # 두 번째 실행 = 같은 바이트
        assert open(feed).read() == first, "finalize is not idempotent"
        assert first.count("<sparkle:minimumSystemVersion>") == 1, "old minimumSystemVersion not replaced"
        # 반례: 다른 빌드 번호·길이·두 항목은 거부돼야 한다.
        for bad in (
            lambda: run(feed, "o/r", "legacy-v0.11.2-3", dmg, "0.11.2", "114.4"),
            lambda: run(feed, "o/r", "legacy-v0.11.2-4", dmg, "0.11.2", "114.3"),
        ):
            try:
                bad()
            except SystemExit:
                continue
            raise AssertionError("mismatched candidate was accepted")
        with open(feed, "w") as handle:
            handle.write(SAMPLE.replace("</item>", "</item><item><enclosure url='x'/></item>"))
        try:
            run(feed, "o/r", "legacy-v0.11.2-3", dmg, "0.11.2", "114.3")
        except SystemExit:
            pass
        else:
            raise AssertionError("two-item feed was accepted")
    print("✅ legacy-appcast-finalize: selftest passed")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    elif len(sys.argv) == 7:
        run(*sys.argv[1:])
    else:
        sys.exit("usage: legacy-appcast-finalize.py <appcast.xml> <owner/repo> <release-tag> <dmg> <short> <build> | --selftest")
