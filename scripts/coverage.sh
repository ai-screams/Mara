#!/usr/bin/env bash
# MaraCore 코드 커버리지 리포트 + 플로어 게이트.
# `swift test --enable-code-coverage` 산출물(profdata + xctest 바이너리)을 읽어 Sources/의
# 라인 커버리지를 계산하고, COVERAGE_MIN 미만이면 CI를 실패시킨다.
#
# 자체 완결 — 외부 서비스(Codecov 등) 없이 llvm-cov만 사용. 리포트는 CI Step Summary에 남긴다.
# 전체 평균 외에 핵심 세션/전원/네트워크 파일별 하한도 적용한다. 포맷터 고커버리지가
# 제품 핵심의 실패 경로 공백을 가리는 것을 막는다.
set -euo pipefail

MIN="${COVERAGE_MIN:-80}"
cd "$(dirname "$0")/../MaraCore"

BIN_PATH="$(swift build --show-bin-path)"
PROF="$BIN_PATH/codecov/default.profdata"
XCTEST="$(find "$BIN_PATH" -maxdepth 1 -name '*.xctest' | head -1)"
BIN="$XCTEST/Contents/MacOS/$(basename "$XCTEST" .xctest)"
if [ ! -f "$PROF" ] || [ ! -x "$BIN" ]; then
  echo "::error::coverage artifacts missing — run 'swift test --enable-code-coverage' first"
  exit 1
fi

REPORT="$(xcrun llvm-cov report "$BIN" -instr-profile "$PROF" Sources/)"
# 판정은 원시값(RAW_COV)으로, 표시만 반올림(COV) — 반올림값을 게이트에 쓰면 79.96%가
# 80.0%로 반올림돼 통과하는 fail-open 틈이 생긴다(표시 눈금 ≠ 판정값).
RAW_COV="$(xcrun llvm-cov export "$BIN" -instr-profile "$PROF" -summary-only Sources/ \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"][0]["totals"]["lines"]["percent"])')"
COV="$(python3 -c "print(round(float('${RAW_COV}'), 1))")"

# 리포트를 CI Step Summary(있으면)와 로그에 남긴다.
{
  echo "### MaraCore line coverage: ${COV}% (floor ${MIN}%)"
  echo ''
  echo '```'
  echo "$REPORT"
  echo '```'
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"

echo "MaraCore line coverage: ${COV}% (floor ${MIN}%)"
overall_ok=true
if python3 -c "import sys; sys.exit(0 if float('${RAW_COV}') >= float('${MIN}') else 1)"; then
  echo "✅ coverage OK"
else
  echo "::error::coverage ${COV}% is below floor ${MIN}% — add tests or adjust COVERAGE_MIN"
  overall_ok=false
fi

file_ok=true
xcrun llvm-cov export "$BIN" -instr-profile "$PROF" -summary-only Sources/ \
  | python3 ../scripts/coverage_file_gate.py \
      --file 'Sources/MaraCore/SleepEngine.swift=95' \
      --file 'Sources/MaraCore/SessionManager.swift=90' \
      --file 'Sources/MaraCore/PowerAssertion.swift=90' \
      --file 'Sources/MaraCore/BatteryMonitoring.swift=75' \
      --file 'Sources/MaraCore/Triggers/RoutingTableNetworkProvider.swift=45' \
  || file_ok=false

[[ "$overall_ok" == true && "$file_ok" == true ]]
