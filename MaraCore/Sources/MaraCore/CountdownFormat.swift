import Foundation

/// 남은 시간의 카운트다운 표기와 다음 갱신 시점. 라벨은 **정확한 남은 시간**(분 반올림)이고,
/// 갱신 시점만 경계 정렬된다: 5분 초과 구간은 5분 경계(5h → 4h55m → …), 마지막 5분은 1분 경계.
/// 올림 라벨링을 쓰지 않는 이유: 5분 배수가 아닌 세션(커스텀 47m, Until 대부분)이 시작 직후
/// 과대 표시된다(47m → "50m"). 정확 라벨 + 경계 틱이면 시작은 정직하고 이후 자연히 배수에 안착한다.
public enum CountdownFormat {
    static let coarse: TimeInterval = 5 * 60   // 5분 (5분 초과 구간)
    static let fine: TimeInterval = 60          // 1분 (마지막 5분 구간)

    /// 정확한 남은 시간 라벨. 표기는 DurationFormat.compact 재사용(분 반올림).
    /// 활성 세션의 마지막 1분은 "0m" 대신 "1m"로 바닥 처리(만료는 SessionManager가 알린다).
    public static func label(remaining: TimeInterval) -> String {
        guard remaining.isFinite, remaining > 0 else { return DurationFormat.compact(0) }
        return DurationFormat.compact(max(remaining, fine))
    }

    /// 라벨이 다음에 바뀔 때까지의 시간(타이머 간격). 경계 정렬 — 정확한 순간에 라벨이 바뀐다.
    public static func nextTick(remaining: TimeInterval) -> TimeInterval {
        guard remaining.isFinite, remaining > 0 else { return fine }
        let g = remaining > coarse ? coarse : fine
        let next = ((remaining / g).rounded(.up) - 1) * g   // 바로 아래 경계
        return max(remaining - next, 0.1)                    // 경계 정확 일치 시 0.1초 간격 방지
    }
}
