import XCTest
@testable import Runline

final class PromptFileLoaderTests: XCTestCase {
    func testLoadsUTF8TextFilesAndSkipsBinaryFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let textURL = directory.appendingPathComponent("notes.md")
        let binaryURL = directory.appendingPathComponent("image.bin")
        try Data("# Notes\nReview the launch flow.".utf8).write(to: textURL)
        try Data([0, 1, 2, 3, 0]).write(to: binaryURL)

        let result = PromptFileLoader.loadFiles(from: [textURL, binaryURL])

        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.files[0].filename, "notes.md")
        XCTAssertEqual(result.files[0].text, "# Notes\nReview the launch flow.")
        XCTAssertEqual(result.skippedFilenames, ["image.bin"])
    }

    func testKeepsOnlyFiveFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let urls = try (0..<6).map { index in
            let url = directory.appendingPathComponent("file-\(index).txt")
            try Data("file \(index)".utf8).write(to: url)
            return url
        }

        let result = PromptFileLoader.loadFiles(from: urls)

        XCTAssertEqual(result.files.count, 5)
        XCTAssertEqual(result.skippedFilenames, ["file-5.txt"])
    }
}
