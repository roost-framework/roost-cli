import Foundation

/// Discovers the Roost project structure from the current directory.
enum ProjectDiscovery {

    /// Finds the project root by looking for Package.swift.
    static func findRoot(from dir: String = FileManager.default.currentDirectoryPath) -> String? {
        var candidate = URL(fileURLWithPath: dir).standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                return candidate.path
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { return nil }
            candidate = parent
        }
    }

    /// Extracts the main executable target name from Package.swift.
    static func findAppName(in root: String) -> String? {
        let packagePath = (root as NSString).appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOfFile: packagePath, encoding: .utf8) else {
            return nil
        }

        // Look for .executableTarget(name: "AppName"
        let pattern = #/\.executableTarget\(\s*name:\s*"([^"]+)"/#
        if let match = content.firstMatch(of: pattern) {
            return String(match.output.1)
        }

        // Fallback: look for Sources/<name>/App.swift directories
        let sourcesDir = (root as NSString).appendingPathComponent("Sources")
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: sourcesDir) {
            for entry in entries {
                let appFile = (sourcesDir as NSString)
                    .appendingPathComponent(entry)
                    .appending("/App.swift")
                if FileManager.default.fileExists(atPath: appFile) {
                    return entry
                }
            }
        }

        return nil
    }

    /// Returns the Sources/<AppName> directory path.
    static func sourcesDir(root: String, appName: String) -> String {
        (root as NSString)
            .appendingPathComponent("Sources")
            .appending("/\(appName)")
    }

    /// Returns the Sources/Migrations directory path.
    static func migrationsDir(root: String) -> String {
        (root as NSString)
            .appendingPathComponent("Sources")
            .appending("/Migrations")
    }

    /// The swift-roost release in the app's Package.resolved. `nil` before the first
    /// resolve and for a local checkout, which has no version. SwiftPM keeps a remote
    /// pin after the app switches to a checkout, so the generated Package.swift's
    /// checkout variables are checked first.
    static func resolvedFrameworkVersion(
        root: String, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard environment["ROOST_FRAMEWORK_PATH"] == nil, environment["ROOST_ECOSYSTEM_PATH"] == nil else { return nil }
        struct Resolved: Decodable {
            struct Pin: Decodable {
                struct State: Decodable { let version: String? }
                let identity: String
                let state: State
            }
            let pins: [Pin]
        }
        let path = (root as NSString).appendingPathComponent("Package.resolved")
        guard let data = FileManager.default.contents(atPath: path),
              let resolved = try? JSONDecoder().decode(Resolved.self, from: data) else { return nil }
        return resolved.pins.first { $0.identity == "swift-roost" }?.state.version
    }
}
