import Combine
import Darwin
import Foundation
import Network

public final class RoutingTableNetworkProvider: NetworkIdentityProviding {
    private let subject: CurrentValueSubject<NetworkIdentity?, Never>
    private let monitor: NWPathMonitor

    public init() {
        // Intentional one-shot startup read: runs on the launch/main path before monitor starts.
        subject = CurrentValueSubject(Self.readGatewayIdentity())
        monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.mara.RoutingTableNetworkProvider")
        monitor.pathUpdateHandler = { [weak self] _ in
            let id = Self.readGatewayIdentity() // sysctl stays off-main
            DispatchQueue.main.async { self?.subject.send(id) }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    public var current: NetworkIdentity? { subject.value }
    public var changes: AnyPublisher<NetworkIdentity?, Never> { subject.eraseToAnyPublisher() }

    // MARK: - sysctl routing-table helpers

    /// Matches the BSD ROUNDUP(a) macro: rounds up to the next UInt32-aligned boundary.
    private static func roundup(_ a: Int) -> Int {
        a > 0 ? (1 + ((a - 1) | (MemoryLayout<UInt32>.size - 1))) : MemoryLayout<UInt32>.size
    }

    // M1: private static (was package-internal static)
    private static func readGatewayIdentity() -> NetworkIdentity? {
        guard let gwIP = readDefaultGatewayIP() else { return nil }
        guard let mac = readMACForIP(gwIP) else { return nil }
        return NetworkIdentity(gatewayMAC: mac)
    }

    /// Reads the default IPv4 gateway from the routing table via
    /// sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0).
    /// Walks rt_msghdr entries; returns the gateway sockaddr_in.sin_addr for the
    /// entry whose flags include RTF_GATEWAY and whose destination is 0.0.0.0.
    private static func readDefaultGatewayIP() -> in_addr_t? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0]
        // I2: size query
        var needed = 0
        guard sysctl(&mib, 6, nil, &needed, nil, 0) == 0, needed > 0 else { return nil }
        // I2: allocate with 25 % margin to absorb table growth between queries
        var bufSize = needed + needed / 4
        var buf = [UInt8](repeating: 0, count: bufSize)
        if sysctl(&mib, 6, &buf, &bufSize, nil, 0) != 0 {
            // I2: one retry on ENOMEM (routing table grew between size query and fetch)
            guard Darwin.errno == ENOMEM else { return nil }
            needed = 0
            guard sysctl(&mib, 6, nil, &needed, nil, 0) == 0, needed > 0 else { return nil }
            bufSize = needed + needed / 4
            buf = [UInt8](repeating: 0, count: bufSize)
            guard sysctl(&mib, 6, &buf, &bufSize, nil, 0) == 0 else { return nil }
        }
        // bufSize is now the number of valid bytes written by sysctl

        var offset = 0
        while offset + MemoryLayout<rt_msghdr>.size <= bufSize {
            assert(offset.isMultiple(of: 4)) // M3: BSD 4-byte alignment invariant
            let rtm = buf.withUnsafeBytes { $0.load(fromByteOffset: offset, as: rt_msghdr.self) }
            let msgLen = Int(rtm.rtm_msglen)
            guard msgLen >= MemoryLayout<rt_msghdr>.size, offset + msgLen <= bufSize else { break }
            let msgEnd = offset + msgLen

            if (rtm.rtm_flags & RTF_GATEWAY) != 0 {
                var saOff = offset + MemoryLayout<rt_msghdr>.size
                var dstIP: in_addr_t?
                var gwIP: in_addr_t?

                for bit in 0..<8 {
                    guard (rtm.rtm_addrs & Int32(1 << bit)) != 0 else { continue }
                    guard saOff + 2 <= msgEnd else { break }
                    assert(saOff.isMultiple(of: 4)) // M3: sockaddr walk 4-byte alignment
                    let sa = buf.withUnsafeBytes { $0.load(fromByteOffset: saOff, as: sockaddr.self) }
                    let saLen = Int(sa.sa_len)

                    if bit == 0, sa.sa_family == UInt8(AF_INET) { // RTA_DST
                        // I1: guard declared length and buffer bound before load(as: sockaddr_in)
                        if saLen >= MemoryLayout<sockaddr_in>.size,
                           saOff + MemoryLayout<sockaddr_in>.size <= msgEnd {
                            let sin = buf.withUnsafeBytes { $0.load(fromByteOffset: saOff, as: sockaddr_in.self) }
                            dstIP = sin.sin_addr.s_addr
                        }
                    } else if bit == 1, sa.sa_family == UInt8(AF_INET) { // RTA_GATEWAY
                        // I1: guard declared length and buffer bound before load(as: sockaddr_in)
                        if saLen >= MemoryLayout<sockaddr_in>.size,
                           saOff + MemoryLayout<sockaddr_in>.size <= msgEnd {
                            let sin = buf.withUnsafeBytes { $0.load(fromByteOffset: saOff, as: sockaddr_in.self) }
                            gwIP = sin.sin_addr.s_addr
                        }
                    }

                    saOff += roundup(saLen)
                }

                // Default route: destination 0.0.0.0 (network byte order == 0)
                if let dst = dstIP, dst == 0, let gw = gwIP { return gw }
            }

            offset += msgLen
        }
        return nil
    }

    /// Reads the link-layer (MAC) address for `targetIP` from the ARP/neighbor table via
    /// sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO).
    /// Walks rt_msghdr entries; for the entry whose RTA_DST matches `targetIP`,
    /// extracts the MAC from the RTA_GATEWAY sockaddr_dl
    /// (sdl_data at byte 8 in the struct, offset by sdl_nlen).
    private static func readMACForIP(_ targetIP: in_addr_t) -> String? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        // I2: size query
        var needed = 0
        guard sysctl(&mib, 6, nil, &needed, nil, 0) == 0, needed > 0 else { return nil }
        // I2: allocate with 25 % margin to absorb table growth between queries
        var bufSize = needed + needed / 4
        var buf = [UInt8](repeating: 0, count: bufSize)
        if sysctl(&mib, 6, &buf, &bufSize, nil, 0) != 0 {
            // I2: one retry on ENOMEM (ARP table grew between size query and fetch)
            guard Darwin.errno == ENOMEM else { return nil }
            needed = 0
            guard sysctl(&mib, 6, nil, &needed, nil, 0) == 0, needed > 0 else { return nil }
            bufSize = needed + needed / 4
            buf = [UInt8](repeating: 0, count: bufSize)
            guard sysctl(&mib, 6, &buf, &bufSize, nil, 0) == 0 else { return nil }
        }
        // bufSize is now the number of valid bytes written by sysctl

        var offset = 0
        while offset + MemoryLayout<rt_msghdr>.size <= bufSize {
            assert(offset.isMultiple(of: 4)) // M3: BSD 4-byte alignment invariant
            let rtm = buf.withUnsafeBytes { $0.load(fromByteOffset: offset, as: rt_msghdr.self) }
            let msgLen = Int(rtm.rtm_msglen)
            guard msgLen >= MemoryLayout<rt_msghdr>.size, offset + msgLen <= bufSize else { break }
            let msgEnd = offset + msgLen

            var saOff = offset + MemoryLayout<rt_msghdr>.size
            var dstIP: in_addr_t?
            var macStr: String?

            for bit in 0..<8 {
                guard (rtm.rtm_addrs & Int32(1 << bit)) != 0 else { continue }
                guard saOff + 2 <= msgEnd else { break }
                assert(saOff.isMultiple(of: 4)) // M3: sockaddr walk 4-byte alignment
                let sa = buf.withUnsafeBytes { $0.load(fromByteOffset: saOff, as: sockaddr.self) }
                let saLen = Int(sa.sa_len)

                if bit == 0, sa.sa_family == UInt8(AF_INET) { // RTA_DST
                    // I1: guard declared length and buffer bound before load(as: sockaddr_in)
                    if saLen >= MemoryLayout<sockaddr_in>.size,
                       saOff + MemoryLayout<sockaddr_in>.size <= msgEnd {
                        let sin = buf.withUnsafeBytes { $0.load(fromByteOffset: saOff, as: sockaddr_in.self) }
                        dstIP = sin.sin_addr.s_addr
                    }
                } else if bit == 1, sa.sa_family == UInt8(AF_LINK) { // RTA_GATEWAY → sockaddr_dl
                    // I1: guard ≥8-byte fixed header (for nlen/alen) and full-struct buffer bound
                    // BSD pads each sockaddr to roundup(saLen) so the physical bytes for a
                    // full sockaddr_dl load are always present even when sdl_len < struct size.
                    if saLen >= 8,
                       saOff + MemoryLayout<sockaddr_dl>.size <= msgEnd {
                        let sdl = buf.withUnsafeBytes { $0.load(fromByteOffset: saOff, as: sockaddr_dl.self) }
                        let alen = Int(sdl.sdl_alen)
                        let nlen = Int(sdl.sdl_nlen)
                        if alen == 6 {
                            // sdl_data starts at byte offset 8 within sockaddr_dl
                            // (after sdl_len, sdl_family, sdl_index, sdl_type, sdl_nlen, sdl_alen, sdl_slen)
                            let macStart = saOff + 8 + nlen
                            if macStart + alen <= msgEnd { // defense in depth
                                macStr = (0..<alen)
                                    .map { String(format: "%02x", buf[macStart + $0]) }
                                    .joined(separator: ":")
                            }
                        }
                    }
                }

                saOff += roundup(saLen)
            }

            if let dst = dstIP, dst == targetIP, let mac = macStr { return mac }

            offset += msgLen
        }
        return nil
    }
}
