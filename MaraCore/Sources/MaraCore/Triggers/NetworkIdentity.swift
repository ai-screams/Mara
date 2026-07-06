import Combine

public struct NetworkIdentity: Hashable, Codable {
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
}

public protocol NetworkIdentityProviding: AnyObject {
    var current: NetworkIdentity? { get }
    var changes: AnyPublisher<NetworkIdentity?, Never> { get }
}
