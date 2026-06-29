# Mara

macOS 메뉴바 앱 — Mac이 잠들지 못하게 막는다. Caffeine 계열이지만 **정공법**(공식 IOKit Power Assertion / `pmset` / Carbon / `SMAppService`)만 쓴다. 권한 우회·미문서화 트릭 없음.

> 이름의 유래: 민속에서 *mara*는 잠든 이의 가슴 위에 앉아 안식을 방해하는 악령으로, *nightmare*(night + mare)의 어원이다.

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

## 상태

- **Plan 1 (코어 MVP)**: 토글·타이머·디스플레이↔시스템 분리·저배터리 자동 OFF·로그인 시 시작·설정 창. 코어 유닛 테스트 통과.
- **Plan 2 (예정)**: 트리거 자동화(앱/Wi-Fi/충전/외장 디스플레이) + 수동>트리거 우선순위 + Shortcuts/Focus
- **Plan 3 (예정)**: 닫힌 뚜껑(클램셸) 유지 — 권한 데몬 + lease 기반 복원 안전모델
