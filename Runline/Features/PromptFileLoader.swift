import Foundation
import UniformTypeIdentifiers

struct PromptFileLoadResult: Hashable {
    var files: [PromptFile]
    var skippedFilenames: [String]
}

enum PromptFileLoader {
    static let maxFiles = 5
    static let maxBytesPerFile = 512 * 1024
    static let allowedContentTypes: [UTType] = [.item]

    static func loadFiles(from urls: [URL], existingFiles: [PromptFile] = []) -> PromptFileLoadResult {
        var files = existingFiles
        var skippedFilenames: [String] = []
        let remainingSlots = max(0, maxFiles - existingFiles.count)

        for url in urls.prefix(remainingSlots) {
            let filename = url.lastPathComponent
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  data.count <= maxBytesPerFile,
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii),
                  isTextLike(text) else {
                skippedFilenames.append(filename)
                continue
            }

            let file = PromptFile(
                filename: filename,
                contentType: contentTypeIdentifier(for: url),
                text: text,
                byteCount: data.count
            )

            if !files.contains(where: { $0.filename == file.filename && $0.byteCount == file.byteCount }) {
                files.append(file)
            }
        }

        if urls.count > remainingSlots {
            skippedFilenames.append(contentsOf: urls.dropFirst(remainingSlots).map(\.lastPathComponent))
        }

        return PromptFileLoadResult(files: files, skippedFilenames: Array(Set(skippedFilenames)).sorted())
    }

    private static func contentTypeIdentifier(for url: URL) -> String? {
        guard !url.pathExtension.isEmpty else { return nil }
        return UTType(filenameExtension: url.pathExtension)?.identifier
    }

    private static func isTextLike(_ text: String) -> Bool {
        !text.contains("\u{0000}")
    }
}
