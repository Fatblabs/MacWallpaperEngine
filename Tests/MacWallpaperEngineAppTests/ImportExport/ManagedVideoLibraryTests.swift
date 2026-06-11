import Foundation
@testable import MacWallpaperEngineApp
import Testing

@Suite("ManagedVideoLibrary")
struct ManagedVideoLibraryTests {
    @Test
    func copiesExternalVideoIntoManagedLibrary() throws {
        let sourceURL = try writeTemporaryMovie(named: "sample")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
        }

        let preparedImport = try ManagedVideoLibrary.prepareForImport(sourceURL)
        defer {
            try? FileManager.default.removeItem(at: preparedImport.url)
        }

        #expect(preparedImport.wasCopied)
        #expect(ManagedVideoLibrary.isManagedVideoURL(preparedImport.url))
        #expect(preparedImport.url.deletingLastPathComponent().lastPathComponent == "ImportedVideos")
        #expect(FileManager.default.fileExists(atPath: preparedImport.url.path))
        #expect(try Data(contentsOf: preparedImport.url) == Data([1, 2, 3, 4]))
    }

    @Test
    func reusesExistingManagedCopyForSameExternalSource() throws {
        let sourceURL = try writeTemporaryMovie(named: "same-source")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
        }

        let firstImport = try ManagedVideoLibrary.prepareForImport(sourceURL)
        let secondImport = try ManagedVideoLibrary.prepareForImport(sourceURL)
        defer {
            try? FileManager.default.removeItem(at: firstImport.url)
        }

        #expect(firstImport.wasCopied)
        #expect(secondImport.wasCopied == false)
        #expect(firstImport.url == secondImport.url)
    }

    @Test
    func importedManagedVideoIsNotCopiedAgain() throws {
        let managedURL = try writeManagedMovie(
            directoryName: "ImportedVideos",
            fileName: "already-managed.mov"
        )
        defer {
            try? FileManager.default.removeItem(at: managedURL)
        }

        let preparedImport = try ManagedVideoLibrary.prepareForImport(managedURL)

        #expect(preparedImport.wasCopied == false)
        #expect(preparedImport.url == managedURL)
    }

    @Test
    func generatedSmoothCopyIsNotCopiedAgain() throws {
        let managedURL = try writeManagedMovie(
            directoryName: "GeneratedSmoothCopies",
            fileName: "generated-frame-gen.mov"
        )
        defer {
            try? FileManager.default.removeItem(at: managedURL)
        }

        let preparedImport = try ManagedVideoLibrary.prepareForImport(managedURL)

        #expect(preparedImport.wasCopied == false)
        #expect(preparedImport.url == managedURL)
    }

    private func writeTemporaryMovie(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name).appendingPathExtension("mov")
        try Data([1, 2, 3, 4]).write(to: url)
        return url
    }

    private func writeManagedMovie(directoryName: String, fileName: String) throws -> URL {
        let directory = try ManagedVideoLibrary.managedRootDirectory()
            .appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        try Data([5, 6, 7, 8]).write(to: url)
        return url
    }
}
