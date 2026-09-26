#!/usr/bin/env bash
# 레거시 공개 파이프라인의 게시 단계(P1·P2·P5·P6·P7). release-legacy.yml의 publish job이 `legacy-feed` 잠금 안에서 부른다.
#
#   legacy-publish.sh <legacy-vX.Y.Z-N> <dist 디렉터리: DMG·.sha256·appcast.xml>
#
# 필요한 환경: GH_TOKEN(contents: write), GITHUB_REPOSITORY(owner/repo), GITHUB_SHA(릴리스 태그 커밋).
#
# 쓰기는 두 곳뿐이다 — P5 버전별 릴리스, P6 피드 게시. 나머지는 읽기·검증.
#   P1 판정: legacy-feed 릴리스 없음=bootstrap / 릴리스는 있는데 appcast.xml 없음=damaged(즉시 실패, 자동 재생성 금지 —
#            피드 유실을 첫 설치로 오인하지 않는다) / 둘 다 있음=normal(현재 appcast를 asset ID로 받아 복원용 백업)
#   P2 버전: 후보(DMG 안 Info.plist) < live 본판 appcast 최고 버전(이주가 막히지 않게). normal: 백업 항목 < 후보,
#            같으면 같은 태그 재실행일 때만(백업 enclosure가 이 태그 경로). bootstrap: 후보 N > 다른 모든 legacy-v* N.
#   P5 버전별 릴리스: 이미 있으면 재사용(같은 태그 재실행), 자산은 없을 때만 올리고 있으면 digest가 같아야 한다(다르면
#            실패 — 수동 정리). 세 자산을 asset ID + API digest로 검증하고, 피드가 가리킬 DMG를 내려받아 대조한다.
#   P6 피드: bootstrap=legacy-feed 릴리스 생성(실패하면 이 실행이 만든 것만 지운다), normal=upload --clobber(실패하면 백업 복원).
#            어느 쪽이든 asset ID + digest + octet-stream 다운로드 cmp로 검증한다(고정 URL의 CDN 즉시 일관성은 가정하지 않는다).
#   P7 사후: 작업 전후 저장소 latest 태그가 같고 본판 형식(vX.Y.Z)인지.
# 부분 실패는 **같은 run의 publish job만 재실행**해 복구한다(빌드 산출물이 그대로여야 digest가 맞는다).
set -euo pipefail

TAG="${1:?usage: legacy-publish.sh <legacy-vX.Y.Z-N> <dist dir>}"
DIST="${2:?dist dir required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
TARGET_SHA="${GITHUB_SHA:?GITHUB_SHA required}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FEED_TAG="legacy-feed"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

die() { echo "::error::legacy-publish: $*" >&2; exit 1; }
info() { echo "▸ $*"; }
feedpy() { python3 "$ROOT_DIR/scripts/legacy-feed.py" "$@"; }

tag_info="$("$ROOT_DIR/scripts/legacy-release-tag.sh" "$TAG")" || die "not a legacy release tag: $TAG"
[ "$(echo "$tag_info" | sed -n 's/^KIND=//p')" = release ] || die "publish only runs for legacy-v* tags, not RC: $TAG"
N="$(echo "$tag_info" | sed -n 's/^N=//p')"

DMG="$(find "$DIST" -maxdepth 1 -name '*.dmg' | head -1)"
if [ -z "$DMG" ] || [ ! -f "$DMG.sha256" ] || [ ! -f "$DIST/appcast.xml" ]; then
    die "dist must hold one DMG, its .sha256 and appcast.xml"
fi

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

# 자산 이름 → "id digest state" (없으면 빈 줄). 목록은 API로 매번 새로 읽는다.
asset_line() { # <release tag> <asset name>
    gh api "repos/$REPO/releases/tags/$1" \
        --jq ".assets[] | select(.name == \"$2\") | \"\(.id) \(.digest // \"\") \(.state)\"" 2>/dev/null || true
}

# 올린 자산을 검증: 이름·state == uploaded·API digest == 로컬 sha256·asset ID로 내려받은 바이트 == 로컬.
# 절대 exit하지 않는다 — 실패는 재시도 뒤 return 1. 호출자가 P5에서는 die로, P6에서는 정리·복원으로 바꾼다
# (여기서 exit하면 P6의 정리·복원 분기가 건너뛰어진다). digest 불일치도 재시도한다: --clobber 직후 API가
# 잠시 이전 자산을 돌려줄 수 있다.
verify_asset() { # <release tag> <asset name> <local file>
    local release="$1" name="$2" file="$3" line id digest state want attempt
    want="$(sha256 "$file")"
    for attempt in 1 2 3 4 5; do
        line="$(asset_line "$release" "$name")"
        id=""; digest=""; state=""
        read -r id digest state <<<"$line" || true
        if [ -n "$id" ] && [ "$state" = uploaded ] && [ "${digest#sha256:}" = "$want" ] \
            && gh api -H "Accept: application/octet-stream" "repos/$REPO/releases/assets/$id" >"$WORK/dl" 2>/dev/null \
            && cmp -s "$WORK/dl" "$file"; then
            echo "  ok    $release/$name (asset $id, sha256 $want)"
            return 0
        fi
        echo "::warning::$release/$name not verified yet (asset ${id:-none}, state ${state:-none}, digest ${digest:-none}) — retry $attempt" >&2
        sleep $((attempt * 3))
    done
    echo "::error::$release/$name failed verification against local sha256 $want" >&2
    return 1
}

# P7 전제: 쓰기 전에 latest가 본판 형식임을 확정한다(없거나 조회 실패·레거시면 아무것도 쓰지 않는다).
LATEST_BEFORE="$(gh api "repos/$REPO/releases/latest" --jq .tag_name)" || die "cannot establish the repository latest release"
[[ "$LATEST_BEFORE" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "repository latest is not a main release tag: $LATEST_BEFORE"

# ── P1 판정(읽기만) ──────────────────────────────────────────────────────────
# 404일 때만 bootstrap이다. 네트워크·권한·5xx 같은 다른 실패를 "피드 없음"으로 오판하면 정상 피드 위에
# bootstrap을 시도하게 된다 — 판정할 수 없으면 멈춘다.
if gh api "repos/$REPO/releases/tags/$FEED_TAG" >/dev/null 2>"$WORK/feed.err"; then
    STATE=normal
elif grep -q 'HTTP 404' "$WORK/feed.err"; then
    STATE=bootstrap
else
    cat "$WORK/feed.err" >&2
    die "cannot determine $FEED_TAG state (not a 404)"
fi
if [ "$STATE" = normal ]; then
    line="$(asset_line "$FEED_TAG" appcast.xml)"
    [ -n "$line" ] || die "damaged: $FEED_TAG release exists without appcast.xml — restore it by hand from the newest legacy-v* release's appcast.xml"
    STATE=normal
    read -r feed_id _ _ <<<"$line"
    gh api -H "Accept: application/octet-stream" "repos/$REPO/releases/assets/$feed_id" >"$WORK/backup.xml" \
        || die "could not download current $FEED_TAG/appcast.xml"
fi
info "P1: feed state = $STATE"

# ── P2 버전 단언(DMG 안 Info.plist 기준) ─────────────────────────────────────
mnt="$WORK/mnt"; mkdir -p "$mnt"
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$DMG" >/dev/null
CAND="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$mnt/Mara.app/Contents/Info.plist")"
hdiutil detach "$mnt" >/dev/null
[ "$CAND" = "114.$N" ] || die "DMG build $CAND does not match tag N ($TAG → 114.$N)"

MAIN_FEED="$(sed -nE 's/.*static let mainFeedURL = "([^"]+)".*/\1/p' "$ROOT_DIR/App/LegacySupport.swift")"
[ -n "$MAIN_FEED" ] || die "mainFeedURL not found in App/LegacySupport.swift"
curl -fsSL "$MAIN_FEED" -o "$WORK/main.xml" || die "could not fetch live main appcast"
MAIN_MAX="$(feedpy max "$WORK/main.xml")"
[ "$(feedpy compare "$CAND" "$MAIN_MAX")" = -1 ] || die "candidate $CAND is not older than live main $MAIN_MAX (14+ migration would stall)"
echo "  ok    candidate $CAND < live main $MAIN_MAX"

if [ "$STATE" = normal ]; then
    read -r PREV PREV_URL <<<"$(feedpy item "$WORK/backup.xml")"
    order="$(feedpy compare "$PREV" "$CAND")"
    if [ "$order" = 0 ]; then
        case "$PREV_URL" in
            */releases/download/"$TAG"/*) echo "  ok    previous $PREV == candidate (re-run of $TAG)" ;;
            *) die "live legacy feed already serves $CAND from another tag ($PREV_URL)" ;;
        esac
    elif [ "$order" = -1 ]; then
        echo "  ok    previous legacy $PREV < candidate $CAND"
    else
        die "previous legacy $PREV is newer than candidate $CAND (out-of-order run — nothing published)"
    fi
else
    # 전 페이지를 본다 — 오래된 레거시 릴리스가 최근 N개 밖으로 밀려도 N 단조성을 지킨다.
    all_tags="$(gh api --paginate "repos/$REPO/releases?per_page=100" --jq '.[].tag_name')" || die "cannot list releases"
    others="$(echo "$all_tags" | grep -E '^legacy-v[0-9]+\.[0-9]+\.[0-9]+-[1-9][0-9]?$' | grep -Fvx -- "$TAG" || true)"
    for other in $others; do
        other_n="${other##*-}"
        [ "$N" -gt "$other_n" ] || die "bootstrap: candidate N=$N is not greater than existing $other"
    done
    echo "  ok    bootstrap: N=$N exceeds every other legacy-v* release"
fi

# ── P3/P4 재확인: appcast가 이 DMG의 단일 항목인지(빌드 job이 만든 것 그대로) ─────────
python3 "$ROOT_DIR/scripts/legacy-appcast-finalize.py" "$DIST/appcast.xml" "$REPO" "$TAG" "$DMG" \
    "$(echo "$tag_info" | sed -n 's/^VERSION=//p')" "$CAND"

# ── P5 버전별 릴리스(재실행 가능) ────────────────────────────────────────────
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    info "P5: reusing existing release $TAG (re-run)"
else
    info "P5: creating release $TAG (not latest)"
    gh release create "$TAG" --repo "$REPO" --verify-tag --latest=false --generate-notes \
        --title "Mara $(echo "$tag_info" | sed -n 's/^VERSION=//p') Legacy $N (macOS 10.13–13)"
fi
for file in "$DMG" "$DMG.sha256" "$DIST/appcast.xml"; do
    name="$(basename "$file")"
    line="$(asset_line "$TAG" "$name")"
    if [ -z "$line" ]; then
        gh release upload "$TAG" "$file" --repo "$REPO"
    else
        read -r _ digest _ <<<"$line"
        [ "${digest#sha256:}" = "$(sha256 "$file")" ] \
            || die "$TAG/$name already exists with a different digest — delete it by hand, then re-run"
    fi
    verify_asset "$TAG" "$name" "$file" || die "$TAG/$name did not verify — re-run the publish job"
done
# 피드가 가리킬 enclosure가 정말 이 DMG를 내려주는지(피드의 URL 그대로).
read -r _ ENCLOSURE <<<"$(feedpy item "$DIST/appcast.xml")"
if ! curl -fsSL "$ENCLOSURE" -o "$WORK/enclosure.dmg" || ! cmp -s "$WORK/enclosure.dmg" "$DMG"; then
    die "enclosure URL does not serve the candidate DMG: $ENCLOSURE"
fi
echo "  ok    enclosure serves the candidate DMG"

# ── P6 피드 게시 ─────────────────────────────────────────────────────────────
if [ "$STATE" = bootstrap ]; then
    info "P6: creating $FEED_TAG release at $TARGET_SHA"
    # API로 만들어 **이 실행이 만든 release ID**를 얻는다. 정리는 그 ID와 현재 release ID가 같을 때만 한다 —
    # 커밋 SHA는 실행 식별자가 아니다(여러 태그가 같은 커밋일 수 있다). 생성 자체가 실패하면(이미 있음 등) 지우지 않는다.
    created_id="$(gh api -X POST "repos/$REPO/releases" \
        -f tag_name="$FEED_TAG" -f target_commitish="$TARGET_SHA" -f name="Legacy update feed" \
        -f body="Sparkle appcast for the macOS 10.13–13 legacy build. Not a download — the app reads appcast.xml from here. (created by run ${GITHUB_RUN_ID:-local} for $TAG)" \
        -F draft=false -F prerelease=false -f make_latest=false --jq .id)" \
        || die "could not create the $FEED_TAG release — nothing was removed; inspect and re-run the publish job"
    if ! gh release upload "$FEED_TAG" "$DIST/appcast.xml" --repo "$REPO" \
        || ! verify_asset "$FEED_TAG" appcast.xml "$DIST/appcast.xml"; then
        current_id="$(gh api "repos/$REPO/releases/tags/$FEED_TAG" --jq .id 2>/dev/null || true)"
        if [ -n "$created_id" ] && [ "$current_id" = "$created_id" ]; then
            gh release delete "$FEED_TAG" --repo "$REPO" --yes --cleanup-tag \
                || die "bootstrap publish failed and cleanup of release $created_id failed — remove it by hand"
            die "bootstrap feed publish failed — removed the release this run created ($created_id); re-run the publish job"
        fi
        die "bootstrap feed publish failed and $FEED_TAG is not the release this run created (${current_id:-none} != $created_id) — left untouched"
    fi
else
    info "P6: replacing $FEED_TAG/appcast.xml (backup kept)"
    if ! gh release upload "$FEED_TAG" "$DIST/appcast.xml" --repo "$REPO" --clobber \
        || ! verify_asset "$FEED_TAG" appcast.xml "$DIST/appcast.xml"; then
        # 복원은 파일 이름 자체가 appcast.xml이어야 한다 — `file#label`의 #은 표시 라벨일 뿐 자산 이름을 바꾸지 않는다.
        mkdir -p "$WORK/restore" && cp "$WORK/backup.xml" "$WORK/restore/appcast.xml"
        gh release upload "$FEED_TAG" "$WORK/restore/appcast.xml" --repo "$REPO" --clobber || true
        verify_asset "$FEED_TAG" appcast.xml "$WORK/restore/appcast.xml" \
            || die "feed update failed AND backup restore did not verify — restore $FEED_TAG/appcast.xml by hand from the previous legacy-v* release"
        die "feed update failed — backup restored and verified; re-run the publish job"
    fi
fi

# ── P7 본판 latest 불변 ──────────────────────────────────────────────────────
LATEST_AFTER="$(gh api "repos/$REPO/releases/latest" --jq .tag_name 2>/dev/null || echo none)"
[ "$LATEST_BEFORE" = "$LATEST_AFTER" ] || die "repository latest changed: $LATEST_BEFORE → $LATEST_AFTER"
[[ "$LATEST_AFTER" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "repository latest is not a main release tag: $LATEST_AFTER"
echo "✅ published $TAG (build $CAND) to $FEED_TAG; latest stays $LATEST_AFTER"
