#!/bin/zsh
# 레거시 의존 모듈 빌드: 한 target triple에 대해 COpenCombineHelpers(C++) → OpenCombine 3종 → MaraCore를
# 정적 라이브러리 + .swiftmodule로 만든다. Xcode 27은 10.13 target을 xcodebuild·SwiftPM으로 빌드하지
# 않으므로 swiftc/clang을 직접 부른다.
#
#   legacy-build-modules.sh <target-triple> <out-dir> [--core-optional]
#
# 산출물: <out-dir>/{include,lib}. --core-optional이면 MaraCore 실패를 경고로만 남긴다(포팅 중 legacy-check용).
set -euo pipefail

TARGET="${1:?usage: legacy-build-modules.sh <target-triple> <out-dir> [--core-optional]}"
OUT="${2:?out dir required}"
CORE_OPTIONAL="${3:-}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/legacy-swift-flags.sh"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

(cd "$ROOT_DIR/MaraCore" && swift package resolve >/dev/null)
OC="$ROOT_DIR/MaraCore/.build/checkouts/OpenCombine/Sources"
[[ -d "$OC/OpenCombine" ]] || { print -u2 "OpenCombine checkout not found"; exit 1; }

mkdir -p "$OUT/include/COpenCombineHelpers" "$OUT/lib" "$OUT/obj"
cp "$OC/COpenCombineHelpers/include/"*.h "$OUT/include/COpenCombineHelpers/"
print 'module COpenCombineHelpers {\n  header "COpenCombineHelpers.h"\n  export *\n}' >"$OUT/include/COpenCombineHelpers/module.modulemap"

xcrun clang++ -std=c++17 -target "$TARGET" -isysroot "$SDK" -O2 -w -c \
    -I "$OC/COpenCombineHelpers/include" "$OC/COpenCombineHelpers/COpenCombineHelpers.cpp" \
    -o "$OUT/obj/COpenCombineHelpers.o"
xcrun libtool -static -o "$OUT/lib/libCOpenCombineHelpers.a" "$OUT/obj/COpenCombineHelpers.o" 2>/dev/null

# 모듈 하나 = 정적 라이브러리 + swiftmodule. OpenCombine은 서드파티라 strict-concurrency를 걸지 않는다.
module() { # <name> <flags...> -- <sources...>
    local name="$1"; shift
    local flags=()
    while [[ "$1" != "--" ]]; do flags+=("$1"); shift; done; shift
    xcrun swiftc -target "$TARGET" -sdk "$SDK" -O -parse-as-library -module-name "$name" \
        -emit-library -static -emit-module -emit-module-path "$OUT/include/$name.swiftmodule" \
        -I "$OUT/include" -I "$OUT/include/COpenCombineHelpers" -o "$OUT/lib/lib$name.a" "${flags[@]}" "$@"
}
module OpenCombine -swift-version 5 -suppress-warnings -- ${(f)"$(find "$OC/OpenCombine" -name '*.swift' | sort)"}
module OpenCombineDispatch -swift-version 5 -suppress-warnings -- ${(f)"$(find "$OC/OpenCombineDispatch" -name '*.swift' | sort)"}
module OpenCombineFoundation -swift-version 5 -suppress-warnings -- ${(f)"$(find "$OC/OpenCombineFoundation" -name '*.swift' | sort)"}

if ! module MaraCore "${LEGACY_SWIFT_FLAGS[@]}" -- ${(f)"$(find "$ROOT_DIR/MaraCore/Sources/MaraCore" -name '*.swift' | sort)"} \
    >"$OUT/MaraCore.log" 2>&1; then
    if [[ "$CORE_OPTIONAL" == "--core-optional" ]]; then
        print -u2 "  warn  MaraCore module did not build for $TARGET (see $OUT/MaraCore.log)"; exit 2
    fi
    cat "$OUT/MaraCore.log" >&2; exit 1
fi
print "  ok    modules for $TARGET → $OUT"
