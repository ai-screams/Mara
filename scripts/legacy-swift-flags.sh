# 레거시 swiftc 언어 설정의 단일 출처 — legacy-build-modules.sh·legacy-check.sh·legacy-build-app.sh가 source한다.
# 앱 타깃 설정(project.yml: SWIFT_STRICT_CONCURRENCY=complete)·MaraCore(StrictConcurrency)와 같게 둔다.
LEGACY_SWIFT_FLAGS=(-swift-version 5 -strict-concurrency=complete)
# 대상 조각: x86_64는 10.13(실기), arm64는 11.0(Apple Silicon 최소 OS).
LEGACY_TARGETS=(x86_64-apple-macosx10.13 arm64-apple-macos11)
