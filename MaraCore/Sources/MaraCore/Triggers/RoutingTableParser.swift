import Darwin
import Foundation

/// Pure parser for the BSD PF_ROUTE sysctl tables (routing + ARP/neighbor).
/// Split out from the Combine/NWPathMonitor adapter (`RoutingTableNetworkProvider`)
/// so the offset-walking logic is unit-testable and the memory-safety invariants
/// live in one place. Every read is bounds-checked against the sysctl-reported
/// valid byte count (`buf.count`); malformed data can only cause an early `break`.
enum RoutingTableParser {

    /// Matches the BSD ROUNDUP(a) macro: rounds up to the next UInt32-aligned boundary.
    private static func roundup(_ a: Int) -> Int {
        a > 0 ? (1 + ((a - 1) | (MemoryLayout<UInt32>.size - 1))) : MemoryLayout<UInt32>.size
    }

    /// Fetches a PF_ROUTE sysctl table into a byte buffer.
    /// I2: size query → allocate (+25 % margin) → fetch → one ENOMEM retry
    /// (the table can grow between the size query and the fetch).
    /// Returns the buffer **trimmed to the valid bytes sysctl wrote**, so callers
    /// bound their walk on `buf.count`. Returns nil on failure.
    private static func dumpRoutingTable(mib: [Int32]) -> [UInt8]? {
        var mib = mib
        let nlen = u_int(mib.count)
        var needed = 0
        guard sysctl(&mib, nlen, nil, &needed, nil, 0) == 0, needed > 0 else { return nil }
        var bufSize = needed + needed / 4
        var buf = [UInt8](repeating: 0, count: bufSize)
        if sysctl(&mib, nlen, &buf, &bufSize, nil, 0) != 0 {
            guard Darwin.errno == ENOMEM else { return nil }
            needed = 0
            guard sysctl(&mib, nlen, nil, &needed, nil, 0) == 0, needed > 0 else { return nil }
            bufSize = needed + needed / 4
            buf = [UInt8](repeating: 0, count: bufSize)
            guard sysctl(&mib, nlen, &buf, &bufSize, nil, 0) == 0 else { return nil }
        }
        return Array(buf[0..<bufSize])   // trim to valid bytes; the walk bounds on buf.count
    }

    /// Reads the default IPv4 gateway from the routing table via
    /// sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0).
    /// Walks rt_msghdr entries; returns the gateway sockaddr_in.sin_addr for the
    /// entry whose flags include RTF_GATEWAY and whose destination is 0.0.0.0.
    static func defaultGatewayIP() -> in_addr_t? {
        guard let buf = dumpRoutingTable(mib: [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0]) else { return nil }
        let bufSize = buf.count

        var offset = 0
        while offset + MemoryLayout<rt_msghdr>.size <= bufSize {
            assert(offset.isMultiple(of: 4)) // M3: BSD 4-byte alignment invariant
            let rtm = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self) }
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
                    // I3: read only the 2-byte sockaddr header (sa_len, sa_family) via the
                    // bounds-checked subscript. A full load(as: sockaddr.self) would read 16
                    // bytes behind this 2-byte guard → up to 14B over-read past msgEnd.
                    let saLen = Int(buf[saOff])            // sockaddr.sa_len    (byte 0)
                    let saFamily = buf[saOff + 1]          // sockaddr.sa_family (byte 1)

                    if bit == 0, saFamily == UInt8(AF_INET) { // RTA_DST
                        // I1: guard declared length and buffer bound before load(as: sockaddr_in)
                        if saLen >= MemoryLayout<sockaddr_in>.size,
                           saOff + MemoryLayout<sockaddr_in>.size <= msgEnd {
                            let sin = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: saOff, as: sockaddr_in.self) }
                            dstIP = sin.sin_addr.s_addr
                        }
                    } else if bit == 1, saFamily == UInt8(AF_INET) { // RTA_GATEWAY
                        // I1: guard declared length and buffer bound before load(as: sockaddr_in)
                        if saLen >= MemoryLayout<sockaddr_in>.size,
                           saOff + MemoryLayout<sockaddr_in>.size <= msgEnd {
                            let sin = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: saOff, as: sockaddr_in.self) }
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
    static func macForIP(_ targetIP: in_addr_t) -> String? {
        guard let buf = dumpRoutingTable(mib: [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]) else { return nil }
        let bufSize = buf.count

        var offset = 0
        while offset + MemoryLayout<rt_msghdr>.size <= bufSize {
            assert(offset.isMultiple(of: 4)) // M3: BSD 4-byte alignment invariant
            let rtm = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self) }
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
                // I3: read only the 2-byte sockaddr header (sa_len, sa_family) via the
                // bounds-checked subscript. A full load(as: sockaddr.self) would read 16
                // bytes behind this 2-byte guard → up to 14B over-read past msgEnd.
                let saLen = Int(buf[saOff])            // sockaddr.sa_len    (byte 0)
                let saFamily = buf[saOff + 1]          // sockaddr.sa_family (byte 1)

                if bit == 0, saFamily == UInt8(AF_INET) { // RTA_DST
                    // I1: guard declared length and buffer bound before load(as: sockaddr_in)
                    if saLen >= MemoryLayout<sockaddr_in>.size,
                       saOff + MemoryLayout<sockaddr_in>.size <= msgEnd {
                        let sin = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: saOff, as: sockaddr_in.self) }
                        dstIP = sin.sin_addr.s_addr
                    }
                } else if bit == 1, saFamily == UInt8(AF_LINK) { // RTA_GATEWAY → sockaddr_dl
                    // I1: guard ≥8-byte fixed header (for nlen/alen) and full-struct buffer bound
                    // BSD pads each sockaddr to roundup(saLen) so the physical bytes for a
                    // full sockaddr_dl load are always present even when sdl_len < struct size.
                    if saLen >= 8,
                       saOff + MemoryLayout<sockaddr_dl>.size <= msgEnd {
                        let sdl = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: saOff, as: sockaddr_dl.self) }
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
