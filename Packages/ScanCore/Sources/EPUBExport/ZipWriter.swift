import Compression
import Foundation

/// A file to place in a ZIP archive.
struct ZipEntry: Equatable {
    /// Path inside the archive, with `/` separators.
    let path: String
    let data: Data
    /// `false` stores the bytes as they are. EPUB requires this for the
    /// `mimetype` entry so that tools can identify the file by fixed offsets.
    let compress: Bool
}

/// Minimal ZIP writer covering what an EPUB container needs: stored and
/// deflated entries, UTF-8 names, no ZIP64, no encryption.
///
/// Written in-house because Foundation has no ZIP API and the project avoids
/// third-party dependencies. Output is deterministic: entry timestamps are
/// fixed, so the same input always gives the same bytes.
enum ZipWriter {
    static func archive(_ entries: [ZipEntry]) -> Data {
        var archive = Data()
        var centralDirectory = Data()
        for entry in entries {
            let name = Data(entry.path.utf8)
            let deflated = entry.compress ? deflate(entry.data) : nil
            let payload = deflated ?? entry.data
            var header = Data()
            header.append(littleEndian: UInt16(20)) // version needed: 2.0
            header.append(littleEndian: UInt16(0x0800)) // flags: UTF-8 names
            header.append(littleEndian: UInt16(deflated == nil ? 0 : 8)) // method
            header.append(littleEndian: UInt16(0)) // time 00:00:00
            header.append(littleEndian: UInt16(0x0021)) // date 1980-01-01
            header.append(littleEndian: crc32(entry.data))
            header.append(littleEndian: UInt32(payload.count))
            header.append(littleEndian: UInt32(entry.data.count))
            header.append(littleEndian: UInt16(name.count))
            header.append(littleEndian: UInt16(0)) // extra field length

            let offset = UInt32(archive.count)
            archive.append(littleEndian: UInt32(0x0403_4B50))
            archive.append(header)
            archive.append(name)
            archive.append(payload)

            centralDirectory.append(littleEndian: UInt32(0x0201_4B50))
            centralDirectory.append(littleEndian: UInt16(20)) // version made by
            centralDirectory.append(header)
            centralDirectory.append(littleEndian: UInt16(0)) // comment length
            centralDirectory.append(littleEndian: UInt16(0)) // disk number
            centralDirectory.append(littleEndian: UInt16(0)) // internal attributes
            centralDirectory.append(littleEndian: UInt32(0)) // external attributes
            centralDirectory.append(littleEndian: offset)
            centralDirectory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.append(littleEndian: UInt32(0x0605_4B50))
        archive.append(littleEndian: UInt16(0)) // this disk
        archive.append(littleEndian: UInt16(0)) // directory disk
        archive.append(littleEndian: UInt16(entries.count))
        archive.append(littleEndian: UInt16(entries.count))
        archive.append(littleEndian: UInt32(centralDirectory.count))
        archive.append(littleEndian: directoryOffset)
        archive.append(littleEndian: UInt16(0)) // comment length
        return archive
    }

    /// Standard CRC-32 (IEEE 802.3), as ZIP requires.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    /// Raw DEFLATE of `data`, or `nil` when compression does not make it
    /// smaller (already-compressed images, empty files), in which case the
    /// caller stores the bytes instead.
    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        // A destination as large as the source is enough: a result that does
        // not fit would not be worth using anyway.
        var destination = [UInt8](repeating: 0, count: data.count)
        let written = data.withUnsafeBytes { source -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(
                &destination, destination.count,
                base, data.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard written > 0, written < data.count else { return nil }
        return Data(destination[..<written])
    }
}

private extension Data {
    mutating func append(littleEndian value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
