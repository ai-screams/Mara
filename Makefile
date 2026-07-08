# 코어 유닛 테스트 (빠름)
test:
	cd MaraCore && swift test

# Xcode 프로젝트 생성 (project.yml -> Mara.xcodeproj, gitignored)
generate:
	xcodegen generate

# 컴파일 검증 (무서명). 권한 테스트는 안정 서명 빌드로 할 것 — README 참조.
build: generate
	xcodebuild -project Mara.xcodeproj -scheme Mara -configuration Debug CODE_SIGNING_ALLOWED=NO build

# 배포본(DMG) 생성: Developer ID 서명 + 공증 + DMG. 자격/사용법은 RELEASING.md 참조.
release:
	./scripts/release.sh

.PHONY: test generate build release
