import Combine

public struct NetworkIdentity: Hashable, Sendable {
    public let gatewayMAC: String
    public init(gatewayMAC: String) {
        self.gatewayMAC = NetworkIdentity.normalize(gatewayMAC)
    }
    /// "0:10:DB:ff:10:2" → "00:10:db:ff:10:02"
    static func normalize(_ raw: String) -> String {
        raw.split(separator: ":", omittingEmptySubsequences: false)
            .map { octet in
                let s = octet.lowercased()
                return s.count == 1 ? "0" + s : String(s)
            }
            .joined(separator: ":")
    }
    /// 정규형 MAC인가: 소문자 hex 두 자리 옥텟 6개. `normalize`는 표기만 맞출 뿐 형식을 검증하지 않는다.
    static func isCanonical(_ mac: String) -> Bool {
        let octets = mac.split(separator: ":", omittingEmptySubsequences: false)
        return octets.count == 6 && octets.allSatisfy { octet in
            octet.utf8.count == 2 && octet.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }
}

@MainActor
public protocol NetworkIdentityProviding: AnyObject {
    var current: NetworkIdentity? { get }
    var changes: AnyPublisher<NetworkIdentity?, Never> { get }
}
