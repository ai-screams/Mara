# Mara — Claude Code notes

## Build & test

- `scripts/generate-project.sh` 필수 선행 — `Mara.xcodeproj`는 생성물(gitignored)이고,
  helper가 커밋된 SwiftPM revision lock을 복원한다. `make test|generate|build|release`.
- 단일 테스트: `cd MaraCore && swift test --filter <TestName>`.
- 로컬 스모크: Release 빌드 후 반드시 Apple Development 정체성으로 재서명(ad-hoc 금지, 글로벌 규칙).
  정체성 조회: `security find-identity -v -p codesigning` (Apple Development 항목 사용).
  Sparkle 중첩 코드를 inside-out으로 먼저: Frameworks의 `*.xpc`/`Autoupdate` → `Sparkle.framework` → 앱 순.
- 로컬 실행 서명은 **처음부터 서명해 빌드가** 정공법: `xcodebuild … CODE_SIGN_STYLE=Manual
  "CODE_SIGN_IDENTITY=Developer ID Application" DEVELOPMENT_TEAM=7K6MK3KP9K build` — 중첩 Sparkle까지 xcodebuild가
  올바로 서명한다(위 inside-out 수동 재서명은 '이미 빌드된 산출물 사후 재서명'일 때만). Apple Development '자동'
  서명은 이 맥에서 실패(그 팀 Xcode 계정 없음) — 실행 앱·release.sh와 같은 Developer ID(7K6MK3KP9K)를 쓴다.
- 실행 교체 전 `pgrep -x Mara` 확인 → `osascript -e 'tell application "Mara" to quit'` → **quit 후 pgrep 재확인**
  (quit이 종료 완료 전 반환할 수 있음 — 중복 인스턴스가 라이브 Mara를 죽인 실사고 있음) → 교체 → `open`.
- 로컬 Release 리빌드가 **기존 서명 번들** 위에서 `"Operation not permitted"`(AppIcon.icns 복사 등)로 실패하면,
  App Management TCC가 서명된 `.app`의 **in-place 수정을** 막는 것이다(uchg 플래그 아님). 정공법 = stale 번들을
  `rm -rf`(삭제는 허용 — 우회 아님)한 뒤 **클린 리빌드**(실행 중이면 먼저 quit). 실사고 1회(B→C 배포 중).
- 더 안전한 정공법: 로컬 App 빌드/스모크는 **격리 `-derivedDataPath`(scratchpad)로** 하라 — 라이브 Mara가 도는
  공유 DerivedData(`~/Library/.../Products/Release/Mara.app`)를 안 건드려 위 TCC in-place 차단·라이브 앱 손상을
  동시에 회피. 격리 빌드로 **성공+심볼 검증 후에만** quit→pgrep 확인→교체(다운타임 0, 검증 전 교체 금지).
- QA 빌드 설치 전 **산출물 심볼 검증** 필수: `grep -c -a '<새 셀렉터/타입명>' <APP>/Contents/MacOS/Mara` ≥1 확인 후 설치.
  서브에이전트는 각자 derivedDataPath에 빌드하므로 컨트롤러 경로의 산출물은 낡았을 수 있다(실사고 1회).
  유니코드 포함 문자열("Custom…" 등)은 strings|grep에 안 잡힘 — ASCII 심볼명으로 검사.
  최적화(-O) Release에선 짧은 문자열(≤15B, 예 "Icon Color")도 Swift SmallString로 인라인돼 grep에 안 잡힌다
  — Debug(`.debug.dylib`)엔 남지만 Release는 셀렉터/타입명(`setMenuBarTint`·`MenuBarTint`)으로 검증(실사고 1회).
  Debug 빌드는 코드가 `Mara.debug.dylib`에 있고 `Contents/MacOS/Mara`는 얇은 런처 — Debug 산출물 심볼 grep은
  `.debug.dylib` 대상(또는 MacOS 디렉터리 `grep -r`). thin 런처만 grep하면 false 0(실사고 1회).
- xcodebuild·git은 리포 루트에서 실행 — cwd는 셸 호출 간 지속·백그라운드로 상속됨(MaraCore에 남아 무실행 실사고 1회).
  파이프(`| tail`)가 exit code를 삼키므로 컴파일 검증은 "BUILD SUCCEEDED" 문자열 확인으로 판정.
- Core `swift test`는 App(AppKit/SwiftUI) 컴파일을 검증 안 함 — Core enum에 케이스 추가(예:
  `SessionFailure`)하거나 App 파일 변경 시 반드시 App strict 빌드로 확인. `switch` 누락·SwiftUI
  깨짐은 여기서만 잡힌다: `xcodebuild … CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build` → "BUILD SUCCEEDED" 확인.
- 파일별 커버리지 게이트(`scripts/coverage.sh` → `coverage_file_gate.py`)는 **CI 전용**(`make test`는 안 돌림).
  IOKit 등 OS 어댑터 파일은 헤드리스 CI 러너에서 하드웨어 의존 분기가 죽어 로컬보다 낮게 나온다
  — 실사고: `BatteryMonitoring.swift` 로컬 84% / CI 73.2%로 75% 플로어에 걸림. **정공법은 floor를 낮추는
  게 아니라 순수 로직을 OS 호출에서 분리해 유닛테스트하는 것** — `read()`에서 `IOKitBatteryMonitor.parse(_:)`를
  분리해 CI 80.2%로 통과. 검증 요령: `swift test --filter <순수테스트>`만 돌려 IOKit 경로가 실행 0회인
  상태에서 순수 함수 본문이 covered면 CI에서도 커버된다는 증거.

## Architecture (배치 규칙)

- 로직·결정은 `MaraCore/`(OS-free, 프로토콜 뒤, 테스트 가능) — App은 얇은 AppKit 셸. 의존 방향은 App→Core 단방향만.
- OS 어댑터 추가 시: Core에 프로토콜 정의 → App(`AppEnvironment`)에서 인스턴스화 주입 (기존 Battery/Screen/Apps/Network 패턴).
- `@Published`는 willSet 발화 — sink에서 재-read 금지, 방출값을 그대로 사용 (기존 코드 주석 참조).
- Core 연산(`SessionManager.start`/`stop`/`toggle`/`updateScope`)은 `Result<_, SessionFailure>`를 반환하고,
  부작용(assertion 적용/해제)이 확정된 뒤에만 state를 바꾼다(`SleepEngine.apply`는 한 단계 아래에서
  `Result<_, SleepEngineFailure>`를 반환 — SessionManager가 `.power(_)`로 감싼다). App 레이어
  (`SessionFailureText`)가 실패를 문구로 매핑 — UI 문자열은 Core에 넣지 않는다(기존 규칙과 동일).
- SwiftUI 시트에 클릭 시점 데이터를 전달할 땐 `.sheet(item:)` — isPresented+별도 @State는 첫 표시가
  낡은(빈) 상태를 캡처한다(실사고: 빈 피커 — 리뷰 4회 통과 후 실기기에서만 발현, RunningAppPicker 주석 참조).
- `BatterySnapshot.isOnAC`는 `.unavailable`에서도 `false` — 저배터리 veto 판정은 `!snap.isOnAC`가
  아니라 `case .battery(...)` 패턴 매칭으로 할 것(안 그러면 데스크톱/IOPS 읽기실패 시 전 세션 시작이
  오거부됨). `SessionManager.batteryFloorBreach` 참조, 테스트로 고정됨.

## Release (CI가 정본)

- 태그 푸시(vX.Y.Z) → 보호된 `release` 환경. 승인: UI 또는 `gh api repos/…/actions/runs/<id>/pending_deployments`.
  CLI 승인 시 `-F "environment_ids[]=<id>"` — 정수 필드라 `-F` 필수(`-f`는 문자열 전송 → 422, 실사고 1회).
- 릴리스 노트는 release.yml의 `generate_release_notes`가 PR 제목 기반으로 자동 생성(이미 있음).
  release-please류 도입은 검토 후 보류 — 근거·재검토 조건은 BACKLOG.md.
- 버전 정본은 git 태그: release.sh가 MARKETING_VERSION을 태그로 덮어씀(project.yml 값은 dev 전용).
  CFBundleVersion = git 커밋 수(단조 증가) — 커밋 없이 연속 태그 금지.
- v* 태그는 룰셋으로 불변 — 실패한 릴리스는 태그 재사용 불가, 패치 범프로 복구(RELEASING.md).
- 태그 푸시(불변) 전 파이프라인 사전점검: `git diff --stat v<직전>..HEAD -- .github/workflows/release.yml
  scripts/release.sh App/Info.plist project.yml` — 비어있으면 릴리스 경로가 직전 성공본과 byte-identical(실패 리스크 최소).
- **검증은 게시된 산출물로**: `gh release download` → spctl/stapler/appcast/`.background` 확인.
  로컬 재현 검증은 이 리포에서 두 번 틀렸다(메뉴바 오렌지, DMG 배경).
- appcast 검증 시 `sparkle:version`은 **자식 엘리먼트**(`<sparkle:version>N</sparkle:version>`)지 속성 아님 —
  속성 grep(`sparkle:version="…"`)은 빈 결과. shortVersionString도 동일. edSignature만 enclosure 속성.
- `scripts/release.sh`는 **zsh**: `${VAR:+--flag "$VAR"}`는 단어 분리 안 됨 — 인자는 배열로 구성.
- codesign 서명 검증: Hardened Runtime 신호는 `flags=…(runtime)`(CodeDirectory 플래그)이지 `Runtime Version=`
  (SDK 버전)이 아니다. leaf 인증서는 `Authority=Developer ID Application`, `…Certification Authority`는 중간 CA.
- PR CI 상태 폴링: `gh pr checks`의 탭 출력을 `awk '{print $2}'`로 파싱 금지 — 체크명 "Build & Test"의
  공백이 필드를 밀어 상태가 "&"로 잡혀 **조기 종료한다**(실사고 2회). `gh pr view <n> --json statusCheckRollup`을
  쓰되, 실행 중 `.conclusion`은 null이 아니라 **빈 문자열이라** jq `// "RUNNING"` 폴백이 안 먹는다 —
  완료 판정은 `.status=="COMPLETED"`로 할 것.
- 로컬 공증: 암호를 argv에 넣지 말 것 — `NOTARY_PROFILE=mara-notary`(Keychain 프로필) 사용.

## macOS 26 menu-bar quirks (상세는 auto-memory·코드 주석)

- 렌더 확인의 ground truth는 사용자 스크린샷/occlusionState — API 값(isVisible, tint)은 거짓말한다.
- 알림 권한의 ground truth는 전달된 배너 — `com.apple.ncprefs.plist`에 앱이 없어도 정상 전달될 수 있다.

## Conventions

- UI 문자열은 영어. 주석은 한국어(메모리 안전/네트워크 파서 계열은 영어).
- 백로그는 `.docs/BACKLOG.md` (.docs는 절대 커밋 금지 — 글로벌 규칙과 동일). 스펙/플랜도 `.docs/`.
- 리뷰·감사(서브에이전트/Codex) 파견 시 사용자가 확정한 설계 결정을 프롬프트에 명시할 것 —
  맥락 없는 감사자는 의도된 결정을 결함으로 보고한다(실사고 1회).
