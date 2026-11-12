@testable import EPUBExport
import Foundation
import Testing

@Suite("ZipWriter")
struct ZipWriterTests {
    private let entries = [
        ZipEntry(path: "mimetype", data: Data("application/epub+zip".utf8), compress: false),
        ZipEntry(path: "dir/текст.txt", data: Data(String(repeating: "hello zip ", count: 500).utf8), compress: true),
        ZipEntry(path: "empty.txt", data: Data(), compress: true),
    ]

    @Test("computes the standard CRC-32")
    func crc() {
        #expect(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(ZipWriter.crc32(Data()) == 0)
    }

    @Test("writes the first entry stored, with its bytes at the fixed EPUB offset")
    func storedFirstEntry() {
        let archive = ZipWriter.archive(entries)
        #expect(Array(archive.prefix(4)) == [0x50, 0x4B, 0x03, 0x04])
        // Compression method (offset 8) is 0 = stored; no extra field (offset 28).
        #expect(archive[8] == 0 && archive[9] == 0)
        #expect(archive[28] == 0 && archive[29] == 0)
        #expect(String(decoding: archive[30 ..< 38], as: UTF8.self) == "mimetype")
        #expect(String(decoding: archive[38 ..< 58], as: UTF8.self) == "application/epub+zip")
    }

    @Test("actually compresses compressible entries")
    func compresses() {
        #expect(ZipWriter.archive(entries).count < 1000)
    }

    @Test("is deterministic")
    func deterministic() {
        #expect(ZipWriter.archive(entries) == ZipWriter.archive(entries))
    }

    @Test("produces an archive the system unzip accepts and reads back unchanged")
    func readableBySystemUnzip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try ZipWriter.archive(entries).write(to: url)

        let test = try Shell.run("/usr/bin/unzip", ["-tq", url.path])
        #expect(test.status == 0, "unzip -t failed: \(String(decoding: test.output, as: UTF8.self))")
        let extracted = try Shell.run("/usr/bin/unzip", ["-p", url.path, "dir/*"])
        #expect(extracted.output == entries[1].data)
    }
}

/// Runs a command-line tool and captures its standard output.
enum Shell {
    static func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}
