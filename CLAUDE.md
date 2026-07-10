# Mara — Claude Code notes

## Build & test

- `xcodegen generate` 필수 선행 — `Mara.xcodeproj`는 생성물(gitignored). `make test|generate|build|release`.
- 단일 테스트: `cd MaraCore && swift test --filter <TestName>`.
- 로컬 스모크: Release 빌드 후 반드시 Apple Development 정체성으로 재서명(ad-hoc 금지, 글로벌 규칙).
  정체성 조회: `security find-identity -v -p codesigning` (Apple Development 항목 사용).
  Sparkle 중첩 코드를 inside-out으로 먼저: Frameworks의 `*.xpc`/`Autoupdate` → `Sparkle.framework` → 앱 순.
- 실행 교체 전 `pgrep -x Mara` 확인 → `osascript -e 'tell application "Mara" to quit'` → 교체 → `open`.
- QA 빌드 설치 전 **산출물 심볼 검증** 필수: `grep -c -a '<새 셀렉터/타입명>' <APP>/Contents/MacOS/Mara` ≥1 확인 후 설치.
  서브에이전트는 각자 derivedDataPath에 빌드하므로 컨트롤러 경로의 산출물은 낡았을 수 있다(실사고 1회).
  유니코드 포함 문자열("Custom…" 등)은 strings|grep에 안 잡힘 — ASCII 심볼명으로 검사.

## Architecture (배치 규칙)

- 로직·결정은 `MaraCore/`(OS-free, 프로토콜 뒤, 테스트 가능) — App은 얇은 AppKit 셸. 의존 방향은 App→Core 단방향만.
- OS 어댑터 추가 시: Core에 프로토콜 정의 → App(`AppEnvironment`)에서 인스턴스화 주입 (기존 Battery/Screen/Apps/Network 패턴).
- `@Published`는 willSet 발화 — sink에서 재-read 금지, 방출값을 그대로 사용 (기존 코드 주석 참조).

## Release (CI가 정본)

- 태그 푸시(vX.Y.Z) → 보호된 `release` 환경. 승인: UI 또는 `gh api repos/…/actions/runs/<id>/pending_deployments`.
- 버전 정본은 git 태그: release.sh가 MARKETING_VERSION을 태그로 덮어씀(project.yml 값은 dev 전용).
  CFBundleVersion = git 커밋 수(단조 증가) — 커밋 없이 연속 태그 금지.
- v* 태그는 룰셋으로 불변 — 실패한 릴리스는 태그 재사용 불가, 패치 범프로 복구(RELEASING.md).
- **검증은 게시된 산출물로**: `gh release download` → spctl/stapler/appcast/`.background` 확인.
  로컬 재현 검증은 이 리포에서 두 번 틀렸다(메뉴바 오렌지, DMG 배경).
- `scripts/release.sh`는 **zsh**: `${VAR:+--flag "$VAR"}`는 단어 분리 안 됨 — 인자는 배열로 구성.
- 로컬 공증: 암호를 argv에 넣지 말 것 — `NOTARY_PROFILE=mara-notary`(Keychain 프로필) 사용.

## macOS 26 menu-bar quirks (상세는 auto-memory·코드 주석)

- 렌더 확인의 ground truth는 사용자 스크린샷/occlusionState — API 값(isVisible, tint)은 거짓말한다.
- 알림 권한의 ground truth는 전달된 배너 — `com.apple.ncprefs.plist`에 앱이 없어도 정상 전달될 수 있다.

## Conventions

- UI 문자열은 영어. 주석은 한국어(메모리 안전/네트워크 파서 계열은 영어).
- 백로그는 `.docs/BACKLOG.md` (.docs는 절대 커밋 금지 — 글로벌 규칙과 동일). 스펙/플랜도 `.docs/`.
