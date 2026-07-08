# Mara

macOS 메뉴바 앱 — Mac이 잠들지 못하게 막는다. Caffeine 계열이지만 **정공법**(공식 IOKit Power Assertion / `pmset` / Carbon / `SMAppService`)만 쓴다. 권한 우회·미문서화 트릭 없음.

> 이름의 유래: 민속에서 *mara*는 잠든 이의 가슴 위에 앉아 안식을 방해하는 악령으로, *nightmare*(night + mare)의 어원이다.

## 설치

1. [릴리스](https://github.com/ai-screams/mara/releases)에서 `Mara-<버전>.dmg`를 내려받는다.
2. dmg를 열고 **Mara**를 `Applications` 폴더로 드래그한다.
3. Launchpad나 Applications에서 Mara를 실행한다 — 메뉴바에 눈 아이콘이 나타난다.

> Developer ID 서명 + Apple 공증이 되어 있어 Gatekeeper 경고 없이 바로 열린다.
> 부팅 시 자동 시작을 원하면 메뉴 ▸ **Launch at Login**을 켠다. 잠들기 방지가 켜지면 눈이 뜨고(주황) 남은 시간이 표시된다.

## 구조

| 모듈 | 책임 |
|---|---|
| `MaraCore` (Swift Package) | OS-free·테스트 가능한 코어. `PowerAssertionProviding`(IOKit `IOPMAssertionCreateWithName`), `SleepEngine`(멱등 assertion reconcile), `SessionManager`(단일 진실 소스: 토글·타이머·저배터리 veto), `BatteryMonitoring`(IOKit.ps), `Scheduling`/`Clock` 추상화 |
| `Mara` (SwiftUI App) | `MenuBarExtra` UI, 설정 창, launch-at-login(`SMAppService`). 글로벌 핫키(Carbon) 코드는 보존하되 현재 비활성화 |

- 최소 지원: **macOS 14+**, Apple Silicon + Intel
- 배포: Developer ID 직배포(notarized) 우선, App Store는 후속

## 개발

```bash
# 코어 유닛 테스트 (빠름)
cd MaraCore && swift test

# Xcode 프로젝트 생성 (project.yml -> Mara.xcodeproj, gitignored)
brew install xcodegen
xcodegen generate

# 컴파일 검증 (무서명)
xcodebuild -project Mara.xcodeproj -scheme Mara -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

> 실행/권한 테스트는 **안정 Apple Development 서명** 빌드로 한다 (ad-hoc 금지 — TCC/로그인항목 권한 꼬임 방지).

## 배포 (릴리스)

Developer ID 서명 + Apple 공증된 `.dmg`로 배포한다(드래그-투-Applications). 전체 절차·CI 자동화는 **[RELEASING.md](RELEASING.md)** 참조.

```bash
# 1회: 공증 자격증명 저장 (앱 암호는 appleid.apple.com ▸ 로그인 및 보안 ▸ 앱 암호).
xcrun notarytool store-credentials mara-notary \
  --apple-id "<your-apple-id>" --team-id 7K6MK3KP9K --password "<app-specific-password>"

# 로컬 릴리스 → dist/Mara-<버전>.dmg (Gatekeeper clean)
DEVELOPMENT_TEAM=7K6MK3KP9K NOTARY_PROFILE=mara-notary make release
```

또는 태그를 밀면 GitHub Actions가 서명·공증·릴리스를 자동화한다(보호된 `release` 환경 + 승인 게이트):
`git tag v1.0.0 && git push origin v1.0.0`. 버전은 태그에서 온다.

## 상태

- **Plan 1 / 1.5 (코어 + 하드닝)**: 토글·타이머·디스플레이↔시스템 분리·저배터리 자동 OFF·로그인 시 시작·설정 창. durable `TriggerEngine`(suppression/re-arm, 수동 > 트리거 우선순위).
- **Plan 2A / 2B (트리거 자동화)**: 충전(AC)·외장 디스플레이·특정 앱 실행·특정 네트워크(게이트웨이 MAC — CoreLocation 권한 불필요)에서 자동 keep-awake.
- 메뉴바 눈 아이콘(활성 = 뜬 눈·주황 + 남은 시간 / 비활성 = 감은 눈), 코어 유닛 + 실제 IOKit 통합 테스트.
- **Plan 3 (보류)**: 닫힌 뚜껑(클램셸) 유지 — 권한 데몬 + lease 기반 복원 안전모델. 사용자 결정으로 연기.
