# 코어 유닛 테스트 (빠름)
test:
	cd MaraCore && swift test

# Xcode 프로젝트 생성 (project.yml -> Mara.xcodeproj, gitignored)
generate:
	./scripts/generate-project.sh

# 컴파일 검증 (무서명). 권한 테스트는 안정 서명 빌드로 할 것 — README 참조.
build: generate
	xcodebuild -project Mara.xcodeproj -scheme Mara -configuration Debug \
		-disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build

# 배포본(DMG) 생성: Developer ID 서명 + 공증 + DMG. 자격/사용법은 RELEASING.md 참조.
release:
	./scripts/release.sh

# 레거시 10.13 로컬 컴파일 검사(Xcode 27은 10.13 target xcodebuild를 거부 — swiftc 직접 호출)
legacy-check:
	./scripts/legacy-check.sh

# 레거시 실기 시험 앱(서명, com.aiscream.Mara.legacytest) → build/legacy/Mara.app
legacy-app:
	./scripts/legacy-build-app.sh

.PHONY: test generate build release legacy-check legacy-app
