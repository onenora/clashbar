import Foundation

struct WorkingDirectoryManager {
    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    var rootDirectoryURL: URL {
        homeDirectory.appendingPathComponent("Library/Application Support/clashbar", isDirectory: true)
    }

    var configDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("config", isDirectory: true)
    }

    var logsDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("logs", isDirectory: true)
    }

    var stateDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("state", isDirectory: true)
    }

    func bootstrapDirectories(fileManager: FileManager = .default) throws {
        try createDirectoryIfNeeded(rootDirectoryURL, fileManager: fileManager)
        try createDirectoryIfNeeded(configDirectoryURL, fileManager: fileManager)
        try createDirectoryIfNeeded(logsDirectoryURL, fileManager: fileManager)
        try createDirectoryIfNeeded(stateDirectoryURL, fileManager: fileManager)
    }

    func normalizeAndValidateWithinRoot(_ url: URL, mustBeDirectory: Bool? = nil) throws -> URL {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        let root = rootDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard isDescendantOrEqual(standardized, parent: root) else {
            throw NSError(
                domain: "ClashBar.PathSecurity",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Path escapes ClashBar working directory: \(standardized.path)"]
            )
        }

        if let mustBeDirectory {
            let values = try standardized.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory != mustBeDirectory {
                throw NSError(
                    domain: "ClashBar.PathSecurity",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: mustBeDirectory
                        ? "Expected directory path: \(standardized.path)"
                        : "Expected file path: \(standardized.path)"]
                )
            }
        }

        return standardized
    }

    private func createDirectoryIfNeeded(_ url: URL, fileManager: FileManager) throws {
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                throw NSError(
                    domain: "ClashBar.PathSecurity",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Expected directory but found file: \(url.path)"]
                )
            }
            return
        }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func isDescendantOrEqual(_ child: URL, parent: URL) -> Bool {
        let childComponents = child.pathComponents
        let parentComponents = parent.pathComponents

        guard parentComponents.count <= childComponents.count else { return false }
        return zip(parentComponents, childComponents).allSatisfy { $0 == $1 }
    }
}
