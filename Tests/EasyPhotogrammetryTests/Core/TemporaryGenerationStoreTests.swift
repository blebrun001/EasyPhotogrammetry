import Foundation
import Testing
@testable import EasyPhotogrammetry

@Suite("TemporaryGenerationStore")
struct TemporaryGenerationStoreTests {
    @Test("createWorkspace creates expected directories and output URL")
    func createWorkspace() throws {
        let root = try TestFilesystem.makeTempDirectory(prefix: "temp-store-root")
        defer { TestFilesystem.removeIfPresent(root) }

        let store = TemporaryGenerationStore(rootDirectory: root, cleanOnInit: true)
        let workspace = try store.createWorkspace()

        #expect(FileManager.default.fileExists(atPath: workspace.inputDirectory.path))
        #expect(FileManager.default.fileExists(atPath: workspace.outputDirectory.path))
        #expect(workspace.outputModelURL.pathExtension == "usdz")
    }

    @Test("createWorkspace returns unique directories")
    func createWorkspaceIsUnique() throws {
        let root = try TestFilesystem.makeTempDirectory(prefix: "temp-store-unique")
        defer { TestFilesystem.removeIfPresent(root) }

        let store = TemporaryGenerationStore(rootDirectory: root, cleanOnInit: true)
        let a = try store.createWorkspace()
        let b = try store.createWorkspace()

        #expect(a.inputDirectory != b.inputDirectory)
        #expect(a.outputDirectory != b.outputDirectory)
        #expect(a.outputModelURL != b.outputModelURL)
    }

    @Test("removeInputDirectoryIfPresent removes only input directory")
    func removeInputDirectory() throws {
        let root = try TestFilesystem.makeTempDirectory(prefix: "temp-store-remove")
        defer { TestFilesystem.removeIfPresent(root) }

        let store = TemporaryGenerationStore(rootDirectory: root, cleanOnInit: true)
        let workspace = try store.createWorkspace()

        store.removeInputDirectoryIfPresent(at: workspace.inputDirectory)

        #expect(!FileManager.default.fileExists(atPath: workspace.inputDirectory.path))
        #expect(FileManager.default.fileExists(atPath: workspace.outputDirectory.path))
    }

    @Test("cleanupAll removes root content")
    func cleanupAll() throws {
        let root = try TestFilesystem.makeTempDirectory(prefix: "temp-store-cleanup")
        defer { TestFilesystem.removeIfPresent(root) }

        let store = TemporaryGenerationStore(rootDirectory: root, cleanOnInit: true)
        _ = try store.createWorkspace()
        #expect(FileManager.default.fileExists(atPath: root.path))

        store.cleanupAll()

        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
