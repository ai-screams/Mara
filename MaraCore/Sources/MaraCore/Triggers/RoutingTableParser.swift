import Darwin
import Foundation

/// Pure parser for the BSD PF_ROUTE sysctl tables (routing + ARP/neighbor).
/// Split out from the Combine/NWPathMonitor adapter (`RoutingTableNetworkProvider`)
/// so the offset-walking logic is unit-testable and the memory-safety invariants
/// live in one place. Every read is bounds-checked against the sysctl-reported
/// valid byte count (`buf.count`); malformed data can only cause an early `break`.
/// The `in:` overloads take the raw table bytes so tests can feed hand-built buffers.
enum RoutingTableParser {

    /// The default route's gateway address and the interface the route goes out on.
    /// The interface is kept so the ARP lookup can tell apart the same gateway IP on two
    /// interfaces (e.g. Wi-Fi and Ethernet to different routers that both use 192.168.0.1).
    struct GatewayRoute: Equatable {
        let address: in_addr_t
        let interfaceIndex: UInt16   // rt_msghdr.rtm_index
    }

    /// One rt_msghdr entry whose declared length fits in the buffer.
    private struct Message {
        let header: rt_msghdr
        let addrStart: Int   // first sockaddr, right after the header
        let end: Int         // one past the message's last byte
    }

    /// The RTA_DST and RTA_GATEWAY slots of one message, read only when well-formed.
    private struct Addresses {
        var destination: in_addr_t?
        var gatewayIP: in_addr_t?   // RTA_GATEWAY as sockaddr_in (routing table)
        var gatewayMAC: String?     // RTA_GATEWAY as sockaddr_dl (ARP table)
        var gatewayLinkIndex: UInt16?   // that sockaddr_dl's sdl_index (the interface `arp -a` prints)
    }

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
    static func defaultGateway() -> GatewayRoute? {
        dumpRoutingTable(mib: [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0]).flatMap(defaultGateway(in:))
    }

    /// Returns the gateway sockaddr_in.sin_addr and rtm_index of the first entry whose flags
    /// include RTF_GATEWAY and whose destination is 0.0.0.0.
    static func defaultGateway(in buf: [UInt8]) -> GatewayRoute? {
        for message in messages(in: buf) where (message.header.rtm_flags & RTF_GATEWAY) != 0 {
            let addresses = addresses(of: message, in: buf)
            // Default route: destination 0.0.0.0 (network byte order == 0)
            if addresses.destination == 0, let gateway = addresses.gatewayIP {
                return GatewayRoute(address: gateway, interfaceIndex: message.header.rtm_index)
            }
        }
        return nil
    }

    /// Reads the link-layer (MAC) address of `gateway` from the ARP/neighbor table via
    /// sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO).
    static func mac(for gateway: GatewayRoute) -> String? {
        dumpRoutingTable(mib: [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO])
            .flatMap { mac(for: gateway, in: $0) }
    }

    /// Returns the RTA_GATEWAY sockaddr_dl MAC of the entry whose RTA_DST is the gateway address,
    /// preferring the one on the default route's interface. When no entry carries that interface,
    /// falls back to the first address match, so a kernel that reports the index differently than
    /// expected still resolves the common one-router network.
    static func mac(for gateway: GatewayRoute, in buf: [UInt8]) -> String? {
        var firstAddressMatch: String?
        for message in messages(in: buf) {
            let addresses = addresses(of: message, in: buf)
            guard addresses.destination == gateway.address, let mac = addresses.gatewayMAC else { continue }
            if addresses.gatewayLinkIndex == gateway.interfaceIndex { return mac }
            if firstAddressMatch == nil { firstAddressMatch = mac }
        }
        return firstAddressMatch
    }

    /// Walks rt_msghdr entries, stopping at the first one whose length is shorter than
    /// a header or runs past the buffer.
    private static func messages(in buf: [UInt8]) -> [Message] {
        var result: [Message] = []
        var offset = 0
        while offset + MemoryLayout<rt_msghdr>.size <= buf.count {
            assert(offset.isMultiple(of: 4)) // M3: BSD 4-byte alignment invariant
            let rtm = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self) }
            let msgLen = Int(rtm.rtm_msglen)
            guard msgLen >= MemoryLayout<rt_msghdr>.size, offset + msgLen <= buf.count else { break }
            result.append(Message(header: rtm, addrStart: offset + MemoryLayout<rt_msghdr>.size, end: offset + msgLen))
            offset += msgLen
        }
        return result
    }

    /// Walks the sockaddr list of `message` in RTA_* bit order and reads RTA_DST and RTA_GATEWAY.
    private static func addresses(of message: Message, in buf: [UInt8]) -> Addresses {
        var found = Addresses()
        var saOff = message.addrStart
        for bit in 0..<8 {
            guard (message.header.rtm_addrs & Int32(1 << bit)) != 0 else { continue }
            guard saOff + 2 <= message.end else { break }
            assert(saOff.isMultiple(of: 4)) // M3: sockaddr walk 4-byte alignment
            // I3: read only the 2-byte sockaddr header (sa_len, sa_family) via the
            // bounds-checked subscript. A full load(as: sockaddr.self) would read 16
            // bytes behind this 2-byte guard → up to 14B over-read past message.end.
            let saLen = Int(buf[saOff])            // sockaddr.sa_len    (byte 0)
            let saFamily = buf[saOff + 1]          // sockaddr.sa_family (byte 1)

            switch (bit, saFamily) {
            case (0, UInt8(AF_INET)):              // RTA_DST
                found.destination = inetAddress(at: saOff, length: saLen, end: message.end, in: buf)
            case (1, UInt8(AF_INET)):              // RTA_GATEWAY → sockaddr_in
                found.gatewayIP = inetAddress(at: saOff, length: saLen, end: message.end, in: buf)
            case (1, UInt8(AF_LINK)):              // RTA_GATEWAY → sockaddr_dl
                if let link = linkAddress(at: saOff, length: saLen, end: message.end, in: buf) {
                    found.gatewayMAC = link.mac
                    found.gatewayLinkIndex = link.index
                }
            default:
                break
            }
            saOff += roundup(saLen)
        }
        return found
    }

    /// sockaddr_in.sin_addr, or nil when the declared length or the message is too short.
    private static func inetAddress(at saOff: Int, length saLen: Int, end: Int, in buf: [UInt8]) -> in_addr_t? {
        // I1: guard declared length and buffer bound before load(as: sockaddr_in)
        guard saLen >= MemoryLayout<sockaddr_in>.size,
              saOff + MemoryLayout<sockaddr_in>.size <= end else { return nil }
        return buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: saOff, as: sockaddr_in.self) }.sin_addr.s_addr
    }

    /// The 6-byte link address of a sockaddr_dl as lowercase colon-hex with its sdl_index, or nil.
    private static func linkAddress(at saOff: Int, length saLen: Int, end: Int,
                                    in buf: [UInt8]) -> (mac: String, index: UInt16)? {
        // I1: guard ≥8-byte fixed header (for nlen/alen) and full-struct buffer bound
        // BSD pads each sockaddr to roundup(saLen) so the physical bytes for a
        // full sockaddr_dl load are always present even when sdl_len < struct size.
        guard saLen >= 8,
              saOff + MemoryLayout<sockaddr_dl>.size <= end else { return nil }
        let sdl = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: saOff, as: sockaddr_dl.self) }
        let alen = Int(sdl.sdl_alen)
        let nlen = Int(sdl.sdl_nlen)
        guard alen == 6 else { return nil }
        // sdl_data starts at byte offset 8 within sockaddr_dl
        // (after sdl_len, sdl_family, sdl_index, sdl_type, sdl_nlen, sdl_alen, sdl_slen)
        let macStart = saOff + 8 + nlen
        guard macStart + alen <= end else { return nil } // defense in depth
        let mac = (0..<alen)
            .map { String(format: "%02x", buf[macStart + $0]) }
            .joined(separator: ":")
        return (mac, sdl.sdl_index)
    }
}
