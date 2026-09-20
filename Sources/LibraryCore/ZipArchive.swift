import Foundation

enum ZipArchive {
    struct Entry: Equatable {
        var name: String
        var data: Data
    }

    static func write(_ entries: [Entry], to url: URL) throws {
        var locals = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = checksum(entry.data)
            var local = Data()
            local.append(uint32(0x04034b50))
            local.append(uint16(20))
            local.append(uint16(1 << 11))
            local.append(uint16(0))
            local.append(uint16(0))
            local.append(uint16(0))
            local.append(uint32(crc))
            local.append(uint32(UInt32(entry.data.count)))
            local.append(uint32(UInt32(entry.data.count)))
            local.append(uint16(UInt16(name.count)))
            local.append(uint16(0))
            local.append(name)
            let offset = UInt32(locals.count)
            locals.append(local)
            locals.append(entry.data)

            var header = Data()
            header.append(uint32(0x02014b50))
            header.append(uint16(20))
            header.append(uint16(20))
            header.append(uint16(1 << 11))
            header.append(uint16(0))
            header.append(uint16(0))
            header.append(uint16(0))
            header.append(uint32(crc))
            header.append(uint32(UInt32(entry.data.count)))
            header.append(uint32(UInt32(entry.data.count)))
            header.append(uint16(UInt16(name.count)))
            header.append(uint16(0))
            header.append(uint16(0))
            header.append(uint16(0))
            header.append(uint16(0))
            header.append(uint32(0))
            header.append(uint32(offset))
            header.append(name)
            central.append(header)
        }
        var end = Data()
        end.append(uint32(0x06054b50))
        end.append(uint16(0))
        end.append(uint16(0))
        end.append(uint16(UInt16(entries.count)))
        end.append(uint16(UInt16(entries.count)))
        end.append(uint32(UInt32(central.count)))
        end.append(uint32(UInt32(locals.count)))
        end.append(uint16(0))
        var output = locals
        output.append(central)
        output.append(end)
        try output.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url)
        guard let eocd = rangeOfEOCD(in: data) else {
            throw LibraryError.archive("That file is not a Cardfile archive.")
        }
        let count = int(data, eocd + 10, 2)
        let centralSize = int(data, eocd + 12, 4)
        let centralOffset = int(data, eocd + 16, 4)
        guard centralOffset + centralSize <= data.count else {
            throw LibraryError.archive("That archive is incomplete.")
        }
        var entries: [Entry] = []
        var cursor = centralOffset
        for _ in 0..<count {
            guard cursor + 46 <= data.count, int(data, cursor, 4) == 0x02014b50 else {
                throw LibraryError.archive("That archive is incomplete.")
            }
            let nameLength = int(data, cursor + 28, 2)
            let extraLength = int(data, cursor + 30, 2)
            let commentLength = int(data, cursor + 32, 2)
            let localOffset = int(data, cursor + 42, 4)
            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else {
                throw LibraryError.archive("That archive is incomplete.")
            }
            let name = String(decoding: data[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            guard isSafeName(name) else {
                throw LibraryError.archive("That archive contains an unsafe file name.")
            }
            let payload = try readLocal(data, offset: localOffset, expectedName: name)
            entries.append(Entry(name: name, data: payload))
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func readLocal(_ data: Data, offset: Int, expectedName: String) throws -> Data {
        guard offset + 30 <= data.count, int(data, offset, 4) == 0x04034b50 else {
            throw LibraryError.archive("That archive is incomplete.")
        }
        let nameLength = int(data, offset + 26, 2)
        let extraLength = int(data, offset + 28, 2)
        let size = int(data, offset + 18, 4)
        let start = offset + 30 + nameLength + extraLength
        guard start + size <= data.count else {
            throw LibraryError.archive("That archive is incomplete.")
        }
        let name = String(decoding: data[(offset + 30)..<(offset + 30 + nameLength)], as: UTF8.self)
        guard name == expectedName else {
            throw LibraryError.archive("That archive does not match its index.")
        }
        return data[start..<(start + size)]
    }

    private static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("/") && !name.contains("..") && !name.contains("\\") && !name.contains(":")
    }

    private static func rangeOfEOCD(in data: Data) -> Int? {
        let signature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let start = max(0, data.count - 66_000)
        var index = data.count - 22
        while index >= start {
            if data[index..<(index + 4)].elementsEqual(signature) { return index }
            index -= 1
        }
        return nil
    }

    private static func int(_ data: Data, _ offset: Int, _ width: Int) -> Int {
        var value = 0
        for shift in 0..<width {
            value |= Int(data[offset + shift]) << (8 * shift)
        }
        return value
    }

    private static func uint16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private static func uint32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }

    private static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let table: [UInt32] = {
        (0..<256).map { index in
            var crc = UInt32(index)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (0xEDB8_8320 ^ (crc >> 1)) : (crc >> 1)
            }
            return crc
        }
    }()
}
