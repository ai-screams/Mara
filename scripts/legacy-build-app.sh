#!/bin/zsh
# 레거시판 로컬 시험 빌드: 실기(macOS 10.13 등)에 옮겨 돌려 볼 서명된 Mara.app을 만든다.
#
# Xcode 27은 10.13 target을 거부해 xcodebuild로 만들 수 없다. 그래서 legacy-build-modules.sh로 OpenCombine·MaraCore를
# 조각별 정적 모듈로 만든 뒤 App을 swiftc로 x86_64(10.13)·arm64(11)로 각각 링크해 lipo로 합치고 번들을 조립한다.
# 배포판은 Xcode 26.3(CI 또는 로컬 DEVELOPER_DIR)이 만든다 — 이 빌드는 실기 확인용이다.
#
#   SIGN_IDENTITY="Developer ID Application: …" ./scripts/legacy-build-app.sh
#
# bundle id는 com.aiscream.Mara.legacytest — 실제 앱의 TCC 권한·UserDefaults와 섞이지 않게 한다.
# 산출물: build/legacy/Mara.app (x86_64 + arm64, 최소 10.13 / 11.0). 끝에 번들 게이트를 서명 모드로 돈다.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
source scripts/legacy-swift-flags.sh

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
BUNDLE_ID="${BUNDLE_ID:-com.aiscream.Mara.legacytest}"
MARKETING_VERSION="${MARKETING_VERSION:-0.11.2}"
BUILD_NUMBER="${BUILD_NUMBER:-114.1}"
OUT_DIR="$ROOT_DIR/build/legacy"
WORK="$OUT_DIR/work"
APP="$OUT_DIR/Mara.app"
CONTENTS="$APP/Contents"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$APP" "$WORK"
mkdir -p "$WORK" "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

# 무시되는(gitignore) Mara.xcodeproj가 다른 브랜치(예: v0.11.2의 Sparkle 2.9.4)에서 생성된 채 남아 있을 수 있다 —
# 핀을 단언하고 매번 다시 생성한다.
./scripts/legacy-sparkle-pin.sh >/dev/null
./scripts/generate-project.sh >/dev/null
xcodebuild -resolvePackageDependencies -project Mara.xcodeproj -scheme Mara -derivedDataPath "$WORK/dd" \
    -disableAutomaticPackageResolution >"$WORK/resolve.log" 2>&1
SPARKLE="$(find "$WORK/dd/SourcePackages/artifacts" -name Sparkle.xcframework -maxdepth 4 | head -1)/macos-arm64_x86_64"
[[ -d "$SPARKLE/Sparkle.framework" ]] || { print -u2 "Sparkle xcframework not found"; exit 1; }

APP_FILES=(${(f)"$(find App -name '*.swift' | sort)"})
slices=()
for target in $LEGACY_TARGETS; do
    print "▸ $target"
    mods="$WORK/modules-$target"
    ./scripts/legacy-build-modules.sh "$target" "$mods"
    out="$WORK/Mara-${target%%-*}"
    # rpath 순서: OS 런타임(/usr/lib/swift)이 먼저 — 10.14.4+는 OS 것을, 10.13만 동봉본을 쓴다.
    xcrun swiftc -target "$target" -sdk "$SDK" -O -module-name Mara "${LEGACY_SWIFT_FLAGS[@]}" \
        -I "$mods/include" -I "$mods/include/COpenCombineHelpers" -L "$mods/lib" \
        -lMaraCore -lOpenCombineFoundation -lOpenCombineDispatch -lOpenCombine -lCOpenCombineHelpers -lc++ \
        -F "$SPARKLE" -framework Sparkle \
        -Xlinker -rpath -Xlinker /usr/lib/swift -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
        $APP_FILES -o "$out"
    slices+=("$out")
done
lipo -create $slices -output "$CONTENTS/MacOS/Mara"

print "▸ resources and Info.plist"
xcrun actool App/Assets.xcassets --compile "$CONTENTS/Resources" --platform macosx \
    --minimum-deployment-target 10.13 --app-icon AppIcon \
    --output-partial-info-plist "$WORK/assets.plist" >"$WORK/actool.log"
sed -e "s|\$(MARKETING_VERSION)|$MARKETING_VERSION|" -e "s|\$(CURRENT_PROJECT_VERSION)|$BUILD_NUMBER|" \
    App/Info.plist >"$CONTENTS/Info.plist"
# Xcode 빌드가 자동으로 넣는 키 — 직접 조립이라 여기서 채운다.
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier $BUNDLE_ID" \
    -c "Add :CFBundleExecutable string Mara" \
    -c "Add :CFBundlePackageType string APPL" \
    -c "Add :CFBundleInfoDictionaryVersion string 6.0" \
    -c "Add :CFBundleDevelopmentRegion string en" \
    -c "Add :CFBundleIconFile string AppIcon" \
    -c "Add :CFBundleIconName string AppIcon" \
    "$CONTENTS/Info.plist"
plutil -lint "$CONTENTS/Info.plist" >/dev/null
print -n "APPL????" >"$CONTENTS/PkgInfo"

print "▸ Sparkle.framework"
ditto "$SPARKLE/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"

# 런타임 동봉 + Sparkle(안쪽부터)·dylib·앱 서명은 릴리스와 같은 스크립트가 한다.
./scripts/legacy-bundle-runtime.sh "$APP" "$SIGN_IDENTITY" --resign-sparkle
EXPECT_AUTHORITY="${SIGN_IDENTITY%%:*}" ./scripts/legacy-bundle-gate.sh "$APP" --signed
print "✓ $APP ($MARKETING_VERSION, build $BUILD_NUMBER, $BUNDLE_ID)"
