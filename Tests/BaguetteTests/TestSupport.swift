import Foundation

enum TestFilesystem {
    static func makeTempDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func writeFile(_ url: URL, contents: String = "data") throws {
        try Data(contents.utf8).write(to: url)
    }

    static func removeIfPresent(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
