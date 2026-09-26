import XCTest
@testable import MaraCore

final class LegacyMenuPolicyTests: XCTestCase {

    // MARK: - Low battery

    func test_lowBattery_onGridValue_twentyItems_oneChecked() {
        let items = LegacyMenuPolicy.lowBatteryItems(stored: 50)
        XCTAssertEqual(items.count, 20)
        XCTAssertEqual(items.map(\.percent), Array(stride(from: 5, through: 100, by: 5)))
        XCTAssertEqual(items.filter(\.checked).map(\.percent), [50])
        XCTAssertFalse(items.contains(where: \.isOffGrid))
    }

    func test_lowBattery_offGridValue_shownFirstAndChecked() {
        let items = LegacyMenuPolicy.lowBatteryItems(stored: 7)
        XCTAssertEqual(items.count, 21)
        XCTAssertEqual(items.first, .init(percent: 7, checked: true, isOffGrid: true))
        XCTAssertEqual(items.filter(\.checked).count, 1)
    }

    func test_lowBattery_bounds() {
        XCTAssertEqual(LegacyMenuPolicy.lowBatteryItems(stored: 100).filter(\.checked).map(\.percent), [100])
        XCTAssertEqual(LegacyMenuPolicy.lowBatteryItems(stored: 98).first?.percent, 98)
        // 범위 밖 → clamp(5) → 격자 위라 추가 항목 없음
        let low = LegacyMenuPolicy.lowBatteryItems(stored: 4)
        XCTAssertEqual(low.count, 20)
        XCTAssertEqual(low.filter(\.checked).map(\.percent), [5])
    }

    // MARK: - Watched apps

    private func app(_ id: String?, _ name: String?, prohibited: Bool = false, regular: Bool = true)
        -> LegacyMenuPolicy.RunningApp {
        .init(bundleID: id, name: name, isProhibited: prohibited, isRegular: regular)
    }

    func test_watchedApps_filtersProhibitedSelfNilAndDuplicates_keepsAccessory() {
        let items = LegacyMenuPolicy.watchedAppItems(
            running: [
                app("com.aiscream.Mara", "Mara"),
                app("com.apple.bg", "BG", prohibited: true),
                app(nil, "NoID"),
                app("com.b.app", "Beta"),
                app("com.b.app", "Beta dup"),
                app("com.menu.extra", "Menu Extra", regular: false),
                app("com.a.app", "alpha"),
            ],
            watched: [],
            selfBundleID: "com.aiscream.Mara")
        XCTAssertEqual(items.map(\.bundleID), ["com.a.app", "com.b.app", "com.menu.extra"])  // 독 앱 먼저 → 이름순
        XCTAssertTrue(items.allSatisfy { $0.running && !$0.watched })
    }

    func test_watchedApps_mergesWatched_andAppendsNotRunning_excludingSelf() {
        let watched = ["com.b.app", "com.gone.app", "com.aiscream.Mara"].compactMap(BundleIdentifier.init(validating:))
        let items = LegacyMenuPolicy.watchedAppItems(
            running: [app("com.b.app", "Beta"), app("com.a.app", "Alpha")],
            watched: watched,
            selfBundleID: "com.aiscream.Mara")
        XCTAssertEqual(items.map(\.bundleID), ["com.a.app", "com.b.app", "com.gone.app"])
        XCTAssertEqual(items.map(\.watched), [false, true, true])
        XCTAssertEqual(items.map(\.running), [true, true, false])
    }

    // MARK: - Effective config

    func test_effectiveConfig_selfOnly_needsWatchList() {
        var cfg = TriggerConfig.defaults
        cfg.appRunningEnabled = true
        cfg.addWatchedBundleID("com.aiscream.Mara")
        let effective = LegacyMenuPolicy.effectiveConfig(cfg, selfBundleID: "com.aiscream.Mara")
        XCTAssertTrue(effective.watchedBundleIDs.isEmpty)
        XCTAssertEqual(cfg.watchedBundleIDs.count, 1)          // 저장값은 그대로
        XCTAssertTrue(effective.activeSpecs().isEmpty)          // 항상-참 트리거가 만들어지지 않는다
        XCTAssertEqual(TriggerStatusText.evaluate(.appRunning, config: effective, snapshot: .empty),
                       .needsWatchList(.appRunning))
    }

    // MARK: - Version footer

    func test_versionFooter() {
        XCTAssertEqual(LegacyMenuPolicy.versionFooter(shortVersion: "0.11.2", build: "114.3"), "Mara 0.11.2 Legacy 3")
        XCTAssertEqual(LegacyMenuPolicy.versionFooter(shortVersion: "0.11.2", build: "114.0"), "Mara 0.11.2 (114.0)")
        XCTAssertEqual(LegacyMenuPolicy.versionFooter(shortVersion: "0.11.2", build: "115"), "Mara 0.11.2 (115)")
    }
}
