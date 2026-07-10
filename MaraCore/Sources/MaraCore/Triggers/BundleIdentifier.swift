import Foundation

/// Bundle ID 값 타입 — 형식 검증을 Core에 고정한다(오타·빈 값이 config로 새지 않게).
/// 규칙: trim 후 비어있지 않고, 내부 공백·제어문자가 없을 것.
/// Apple 권고 문자셋([A-Za-z0-9-.])보다 의도적으로 넓다 — OS 로더는 권고를 강제하지 않고
/// 언더스코어 등이 포함된 실존 앱(Electron 계열 등)이 있어, 여기서 좁히면 그런 앱을
/// 감시할 수 없고 업그레이드 시 기존 저장 항목이 소실된다(Codex 감사 지적).
/// 검증 목적은 오타(내부 공백/빈 값) 차단이지 App Store 규정 준수가 아니다.
/// 대소문자는 보존하고 매칭은 exact — 피커가 OS의 정확한 문자열을 제공하므로 정규화하지 않는다.
public struct BundleIdentifier: Hashable, Sendable {
    public let rawValue: String

    private static let rejected = CharacterSet.whitespacesAndNewlines
        .union(.controlCharacters)

    /// 형식 위반이면 nil. 앞뒤 공백·개행은 잘라낸 뒤 검증한다(수동 입력 관용).
    public init?(validating raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: { Self.rejected.contains($0) })
        else { return nil }
        self.rawValue = trimmed
    }
}

/// JSON 표현은 순수 문자열 — 기존 persisted `[String]`과 양방향 호환(마이그레이션 불요).
/// 단독 디코드에서 무효 문자열은 throw한다. 목록 레벨의 안전 축퇴(개별 필터)는
/// TriggerConfig.init(from:)이 [String]으로 받아 compactMap하는 쪽이 담당한다.
extension BundleIdentifier: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let id = BundleIdentifier(validating: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "invalid bundle identifier"
            ))
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
