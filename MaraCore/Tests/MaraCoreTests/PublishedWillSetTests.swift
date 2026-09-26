import OpenCombine
import XCTest
@testable import MaraCore

/// 레거시가 Combine 대신 쓰는 OpenCombine `@Published`도 **willSet 시점에** 방출하는지 고정한다.
/// App(StatusBarController 등)이 "sink 인자 = 새 값, sink 안에서 프로퍼티 재-read = 이전 값"에 기대므로
/// 의미가 바뀌면 여기서 먼저 깨져야 한다.
final class PublishedWillSetTests: XCTestCase {
    private final class Box {
        @OpenCombine.Published var value = 1
    }

    func test_sinkReceivesNewValue_whilePropertyStillHoldsOld() {
        let box = Box()
        var seen: [(emitted: Int, reread: Int)] = []
        let cancellable = box.$value.dropFirst().sink { [unowned box] new in
            seen.append((new, box.value))
        }

        box.value = 2

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.emitted, 2)
        XCTAssertEqual(seen.first?.reread, 1)
        XCTAssertEqual(box.value, 2)
        cancellable.cancel()
    }
}
