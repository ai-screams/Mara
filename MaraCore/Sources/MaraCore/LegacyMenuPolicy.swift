import Foundation

/// 레거시판(메뉴 전용) 메뉴 구성의 순수 결정. 본판 Settings 창에 있던 조작을 메뉴 항목으로 옮길 때
/// "무엇이 보이고 무엇이 체크되는가"를 여기서 정한다 — App은 결과를 `NSMenuItem`으로 옮기기만 한다.
public enum LegacyMenuPolicy {

    // MARK: - Low battery

    public struct BatteryItem: Equatable, Sendable {
        public let percent: Int
        public let checked: Bool
        /// 5% 격자 밖의 저장값(예: 7) — 맨 위에 "(current)"로 보인다. 저장값은 몰래 바꾸지 않는다.
        public let isOffGrid: Bool
    }

    /// `SessionManager.batteryThresholdRange`의 5% 격자 20개 + (저장값이 격자 밖이면) 그 값 하나를 맨 위에.
    /// 저장값은 범위로 clamp해 판정한다(`PrefsStore`의 sanitize와 같은 규칙).
    public static func lowBatteryItems(stored: Int) -> [BatteryItem] {
        let range = SessionManager.batteryThresholdRange
        let value = min(max(stored, range.lowerBound), range.upperBound)
        let grid = Array(stride(from: range.lowerBound, through: range.upperBound, by: 5))
        var items = grid.map { BatteryItem(percent: $0, checked: $0 == value, isOffGrid: false) }
        if !grid.contains(value) {
            items.insert(BatteryItem(percent: value, checked: true, isOffGrid: true), at: 0)
        }
        return items
    }

    // MARK: - Watched apps

    /// 실행 중 앱 한 개의 관측값(`NSRunningApplication`에서 App이 채운다 — Core는 AppKit 타입을 모른다).
    public struct RunningApp: Equatable, Sendable {
        public let bundleID: String?
        public let name: String?
        public let isProhibited: Bool
        public let isRegular: Bool
        public init(bundleID: String?, name: String?, isProhibited: Bool, isRegular: Bool) {
            self.bundleID = bundleID
            self.name = name
            self.isProhibited = isProhibited
            self.isRegular = isRegular
        }
    }

    public struct AppItem: Equatable, Sendable {
        public let bundleID: String
        public let title: String
        public let watched: Bool
        public let running: Bool
    }

    /// "Watched Apps" 서브메뉴. 본판 앱 선택 창(`RunningAppSnapshot.fetch`)과 같은 규칙:
    /// `.prohibited` 제외(`.accessory` 포함), Mara 자신 제외(자기 감시는 항상 참), bundle ID 중복 제거,
    /// 독 앱 먼저 → 이름순. 감시 중인 ID는 체크로 합치고, 실행 중이 아닌 감시 ID만 뒤에 붙인다.
    public static func watchedAppItems(running: [RunningApp],
                                       watched: [BundleIdentifier],
                                       selfBundleID: String?) -> [AppItem] {
        let watchedIDs = Set(watched.map(\.rawValue))
        var seen = Set<String>()
        let live = running
            .filter { !$0.isProhibited }
            .compactMap { app -> (item: AppItem, regular: Bool)? in
                guard let id = app.bundleID, id != selfBundleID, seen.insert(id).inserted else { return nil }
                return (AppItem(bundleID: id, title: app.name ?? id, watched: watchedIDs.contains(id), running: true),
                        app.isRegular)
            }
            .sorted {
                if $0.regular != $1.regular { return $0.regular }
                return $0.item.title.localizedCaseInsensitiveCompare($1.item.title) == .orderedAscending
            }
            .map(\.item)
        let notRunning = watched
            .map(\.rawValue)
            .filter { $0 != selfBundleID && !seen.contains($0) }
            .map { AppItem(bundleID: $0, title: $0, watched: true, running: false) }
        return live + notRunning
    }

    // MARK: - Effective trigger config

    /// 저장된 감시 목록에서 Mara 자신의 ID를 뺀 설정 — 트리거 생성·상태 줄·메뉴가 모두 이 값 하나를 쓴다.
    /// 저장값은 그대로 둔다(본판으로 이주해도 같은 동작이 되도록 평가 단계에서만 거른다).
    public static func effectiveConfig(_ config: TriggerConfig, selfBundleID: String?) -> TriggerConfig {
        guard let selfBundleID else { return config }
        var copy = config
        copy.watchedBundleIDs.removeAll { $0.rawValue == selfBundleID }
        return copy
    }

    // MARK: - Version footer

    /// 메뉴 하단의 비활성 버전 표시. 레거시 빌드 번호 `114.N` → "Mara 0.11.2 Legacy N".
    /// 형식이 다르면(로컬 시험 빌드 등) 빌드 번호를 그대로 붙인다.
    public static func versionFooter(shortVersion: String, build: String) -> String {
        let parts = build.split(separator: ".")
        if parts.count == 2, parts[0] == "114", let n = Int(parts[1]), (1...99).contains(n) {
            return "Mara \(shortVersion) Legacy \(n)"
        }
        return "Mara \(shortVersion) (\(build))"
    }
}
