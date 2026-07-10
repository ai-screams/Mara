import Foundation

/// 세션 지속시간의 압축 표기(15m / 1h / 1h30m). 메뉴바 라벨·메뉴 제목·다이얼로그 미리보기의
/// 단일 출처. 분 단위 반올림 — 초는 이 앱의 도메인에서 의미 없다.
/// 입력은 [0, 24h]로 클램프된다: 음수/비유한은 "0m", 24h 초과는 "24h"로 표시.
public enum DurationFormat {
    public static func compact(_ seconds: TimeInterval) -> String {
        // 방어: 호출부가 가드해도 public API로 NaN/∞/음수/거대값이 올 수 있다 — trap 대신 안전 축퇴.
        guard seconds.isFinite else { return "0m" }
        let clamped = min(max(seconds, 0), 24 * 3600)
        let minutes = Int((clamped / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }
}
