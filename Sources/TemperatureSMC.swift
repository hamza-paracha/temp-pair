//
//  AppleSMC request layout adapted from exelban/stats v3.0.21 (MIT).
//
//  Copyright © 2021 Serhiy Mytrovtsiy. All rights reserved.
//

import Foundation
import IOKit

internal struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8)

    struct vers_t {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct LimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0))
}

// One instance per sampling queue. Only the key-info and read-bytes commands are used.
final class TemperatureSMC {
    private var connection: io_connect_t = 0
    private var info = [UInt32: SMCKeyData_t.keyInfo_t]()

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    private func call(_ input: inout SMCKeyData_t) -> SMCKeyData_t? {
        guard connection != 0 else { return nil }
        var output = SMCKeyData_t()
        let size = MemoryLayout<SMCKeyData_t>.stride
        var received = size
        let result = IOConnectCallStructMethod(connection, 2, &input, size, &output, &received)
        guard result == KERN_SUCCESS, received == size, output.result == 0 else { return nil }
        return output
    }

    func getValue(_ name: String) -> Double? {
        guard name.utf8.count == 4 else { return nil }
        var request = SMCKeyData_t()
        request.key = name.utf8.reduce(0) { $0 << 8 | UInt32($1) }
        let key = request.key
        if info[key] == nil {
            request.data8 = 9 // read key metadata
            guard let reply = call(&request), (1...32).contains(reply.keyInfo.dataSize) else { return nil }
            info[key] = reply.keyInfo
        }
        guard let meta = info[key] else { return nil }
        request.keyInfo.dataSize = meta.dataSize
        request.data8 = 5 // read value
        guard let reply = call(&request) else {
            info.removeValue(forKey: key)
            return nil
        }
        let b = reply.bytes
        switch (meta.dataType, meta.dataSize) {
        case (0x666c7420, 4): // "flt ": little-endian IEEE 754
            let bits = UInt32(b.0) | UInt32(b.1) << 8 | UInt32(b.2) << 16 | UInt32(b.3) << 24
            return Double(Float(bitPattern: bits))
        case (0x73703738, 2): // "sp78": signed big-endian 8.8 fixed point
            return Double(Int16(bitPattern: UInt16(b.0) << 8 | UInt16(b.1))) / 256
        default:
            return nil
        }
    }
}
