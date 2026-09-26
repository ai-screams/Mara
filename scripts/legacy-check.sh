#!/bin/zsh
# 레거시판(macOS 10.13–13) 로컬 컴파일 검사. Xcode 27은 10.13 target의 xcodebuild를 거부하므로
# `make build`는 이 브랜치에서 실패한다 — 대신 이 스크립트가 swiftc를 직접 불러
#   1. 대상 조각(x86_64 10.13, arm64 11)마다 OpenCombine·MaraCore 모듈을 만들고(legacy-build-modules.sh)
#   2. MaraCore와 App 소스를 파일별로 타입 검사하고(전체 모듈 검사는 첫 오류 파일에서 멈춰 나머지를 가린다)
#   3. x86_64 10.13 실행 파일을 링크해 본다(OpenCombine C++ 헬퍼까지 — modulemap만으로는 링크 오류를 못 잡는다).
# 정식 빌드는 Xcode 26.3(CI 또는 로컬 DEVELOPER_DIR)이 한다.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
source scripts/legacy-swift-flags.sh
WORK="${LEGACY_CHECK_DIR:-$ROOT_DIR/build/legacy-check}"
rm -rf "$WORK"; mkdir -p "$WORK"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
FRONTEND="$(xcrun -f swift-frontend)"

# Sparkle 2.9.6 바이너리(xcframework)만 필요 — 해석만 하므로 Xcode 27로도 된다.
[[ -d Mara.xcodeproj ]] || ./scripts/generate-project.sh >/dev/null
xcodebuild -resolvePackageDependencies -project Mara.xcodeproj -scheme Mara -derivedDataPath "$WORK/dd" \
    -disableAutomaticPackageResolution >"$WORK/resolve.log" 2>&1
SPARKLE="$(find "$WORK/dd/SourcePackages/artifacts" -name Sparkle.xcframework -maxdepth 4 | head -1)/macos-arm64_x86_64"
[[ -d "$SPARKLE/Sparkle.framework" ]] || { print -u2 "Sparkle xcframework not found"; exit 1; }

CORE_FILES=(${(f)"$(find MaraCore/Sources/MaraCore -name '*.swift' | sort)"})
APP_FILES=(${(f)"$(find App -name '*.swift' | sort)"})
status_code=0

typecheck() { # <label> <target> <module-name> <extra flags...> -- <files...>
    local label="$1" target="$2" name="$3"; shift 3
    local flags=()
    while [[ "$1" != "--" ]]; do flags+=("$1"); shift; done; shift
    local files=("$@") log="$WORK/typecheck-$label-$target.log" failed=0
    : >"$log"
    for file in $files; do
        if ! "$FRONTEND" -typecheck -primary-file "$file" ${files:#$file} -target "$target" -sdk "$SDK" \
            -module-name "$name" "${LEGACY_SWIFT_FLAGS[@]}" "${flags[@]}" >>"$log" 2>&1; then
            print "$file: frontend exited nonzero" >>"$log"; failed=$((failed + 1))
        fi
    done
    local errors; errors=$(grep -E '^[^ ]+\.swift:[0-9]+:[0-9]+: error:' "$log" | sort -u | wc -l | tr -d ' ')
    print "  $label $target: $errors error(s), $failed file(s) failed"
    if [[ "$errors" != 0 || "$failed" != 0 ]]; then
        grep -E '^[^ ]+\.swift:[0-9]+:[0-9]+: error:' "$log" | sort -u | sed "s|$ROOT_DIR/||" | head -${LEGACY_CHECK_SHOW:-15}
        status_code=1; return 1
    fi
}

for target in $LEGACY_TARGETS; do
    mods="$WORK/modules-$target"
    core_built=1
    ./scripts/legacy-build-modules.sh "$target" "$mods" --core-optional || core_built=0
    inc=(-I "$mods/include" -I "$mods/include/COpenCombineHelpers")
    typecheck core "$target" MaraCore "${inc[@]}" -- $CORE_FILES || true
    if [[ $core_built == 1 ]]; then
        typecheck app "$target" Mara "${inc[@]}" -F "$SPARKLE" -warnings-as-errors -- $APP_FILES || true
    else
        print "  app $target: skipped (MaraCore module not built)"; status_code=1
    fi
done

if [[ $status_code == 0 ]]; then
    mods="$WORK/modules-x86_64-apple-macosx10.13"
    xcrun swiftc -target x86_64-apple-macosx10.13 -sdk "$SDK" -O -module-name Mara "${LEGACY_SWIFT_FLAGS[@]}" \
        -I "$mods/include" -I "$mods/include/COpenCombineHelpers" -L "$mods/lib" \
        -lMaraCore -lOpenCombineFoundation -lOpenCombineDispatch -lOpenCombine -lCOpenCombineHelpers -lc++ \
        -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
        $APP_FILES -o "$WORK/Mara-x86_64" >"$WORK/link.log" 2>&1 \
        || { print "  link x86_64 10.13: FAILED"; grep -E 'error' "$WORK/link.log" | head; exit 1; }
    print "  link x86_64 10.13: ok ($(otool -l "$WORK/Mara-x86_64" | awk '/LC_VERSION_MIN_MACOSX/{f=1} f&&/version/{print $2; exit}'))"
fi
exit $status_code
