import Foundation
import MacWallpaperEngineCore

struct PreparedVideoImport: Sendable {
    let url: URL
    let wasCopied: Bool
}

enum ManagedVideoLibrary {
    static func prepareForImport(_ sourceURL: URL) throws -> PreparedVideoImport {
        guard sourceURL.isFileURL else {
            throw LocalVideoImportError.notAFileURL
        }

        guard LocalVideoImporter.isSupportedLocalVideoURL(sourceURL) else {
            throw LocalVideoImportError.unsupportedFileType(sourceURL.pathExtension.lowercased())
        }

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        if isManagedVideoURL(sourceURL) {
            return PreparedVideoImport(url: sourceURL, wasCopied: false)
        }

        let destinationURL = try importedVideoURL(for: sourceURL)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return PreparedVideoImport(url: destinationURL, wasCopied: false)
        }

        let stagingURL = destinationURL.deletingLastPathComponent().appendingPathComponent(".import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stagingURL) }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: stagingURL)
            try excludeFromBackup(stagingURL)
            try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
        } catch CocoaError.fileWriteFileExists {
            return PreparedVideoImport(url: destinationURL, wasCopied: false)
        }

        return PreparedVideoImport(url: destinationURL, wasCopied: true)
    }

    static func isManagedVideoURL(_ url: URL) -> Bool {
        guard let managedRoot = try? managedRootDirectory().standardizedFileURL.resolvingSymlinksInPath() else {
            return false
        }
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        return ["ImportedVideos", "GeneratedSmoothCopies", "OptimizedSnippets"].contains { folder in
            candidate.path.hasPrefix(managedRoot.appendingPathComponent(folder).path + "/")
        }
    }

    static func managedRootDirectory() throws -> URL {
        AppStorage.root
    }

    static func importedVideosDirectory() throws -> URL {
        let directory = try managedRootDirectory()
            .appendingPathComponent("ImportedVideos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
        return directory
    }

    private static func importedVideoURL(for sourceURL: URL) throws -> URL {
        let directory = try importedVideosDirectory()
        let identity = try sourceIdentity(for: sourceURL)
        let baseName = sanitizedBaseName(sourceURL.deletingPathExtension().lastPathComponent)
        let fileExtension = sourceURL.pathExtension.lowercased()
        return directory
            .appendingPathComponent("\(baseName)-\(identity)")
            .appendingPathExtension(fileExtension)
    }

    private static func sourceIdentity(for sourceURL: URL) throws -> String {
        let values = try sourceURL.resourceValues(forKeys: [
            .fileResourceIdentifierKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let rawValue = [
            sourceURL.standardizedFileURL.resolvingSymlinksInPath().path,
            String(values.fileSize ?? 0),
            String(Int(modifiedAt * 1_000)),
            values.fileResourceIdentifier.map { String(describing: $0) } ?? "no-file-id"
        ].joined(separator: "|")
        return fnv1a64(rawValue)
    }

    private static func sanitizedBaseName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:").union(.newlines)
        let components = name.components(separatedBy: invalidCharacters)
        let sanitized = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "wallpaper-video" : sanitized
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
