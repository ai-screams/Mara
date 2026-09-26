import Foundation
import OpenCombine

// 레거시판(macOS 10.13–13)의 Core 쪽 OS 차이 흡수는 이 파일 하나에서만 한다(App 쪽은 App/LegacySupport.swift).

/// `MainActor.assumeIsolated`(10.15+) 백포트. 10.15+에서는 그대로 위임한다.
///
/// SAFETY(10.15 미만): 그 OS에는 동시성 런타임의 격리 검사가 없다. 메인 큐임을 `dispatchPrecondition`으로
/// 단언(어기면 즉시 트랩 — off-main 방출을 조용히 넘기지 않는다)한 뒤, 같은 클로저를 비격리 함수 타입으로
/// 바꿔(`unsafeBitCast` — 전역 액터 격리는 호출 규약을 바꾸지 않는다) 직접 실행한다.
/// 호출은 main 큐가 구조적으로 보장되는 곳에만 둔다: 진입점(main.swift 최상위), `queue: .main` 알림 관찰,
/// main RunLoop 타이머·CFRunLoop 소스, `DispatchQueue.main` 작업, main에서 동기 방출하는 publisher의 sink.
public func unsafeAssumeMainActor<T>(_ body: @MainActor () throws -> T) rethrows -> T {
    if #available(macOS 10.15, *) {
        return try MainActor.assumeIsolated(body)
    }
    dispatchPrecondition(condition: .onQueue(.main))
    return try withoutActuallyEscaping(body) { escapable in
        try unsafeBitCast(escapable, to: (() throws -> T).self)()
    }
}

// 새 SDK의 Foundation이 Combine의 `Published`·`ObservableObject` 이름을 함께 노출해 OpenCombine과 모호해진다.
// 모듈 안의 선언이 import보다 우선하므로 여기서 OpenCombine 쪽으로 고정한다(App 모듈도 같은 파일을 따로 둔다).
public typealias Published = OpenCombine.Published
public typealias ObservableObject = OpenCombine.ObservableObject
