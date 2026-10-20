import ArgumentParser
import Foundation
@preconcurrency import Noora

struct ProjectContext {
    let root: String
    let appName: String
}

func resolveProject() throws -> ProjectContext {
    guard let root = ProjectDiscovery.findRoot() else {
        RoostUI.noora.error(.alert(
            "No Package.swift found.",
            takeaways: ["Run this command from your project root."]
        ))
        throw ExitCode.failure
    }

    guard let appName = ProjectDiscovery.findAppName(in: root) else {
        RoostUI.noora.error(.alert(
            "Could not determine app name from Package.swift.",
            takeaways: ["Ensure you have an executableTarget or Sources/<AppName>/App.swift."]
        ))
        throw ExitCode.failure
    }

    return ProjectContext(root: root, appName: appName)
}

/// Runs the app's own executable, `swift run <App> <arguments>`, after starting its dev database.
///
/// - Parameter minimumFramework: The swift-roost release that added the command. Older
///   apps ignore unknown arguments and start the server, so they are stopped here instead.
func runApp(_ arguments: [String], database: Bool = true, minimumFramework: String? = nil) throws {
    let context = try resolveProject()
    if let minimumFramework, let resolved = ProjectDiscovery.resolvedFrameworkVersion(root: context.root),
       isVersion(resolved, olderThan: minimumFramework) {
        RoostUI.noora.error(.alert(
            "roost \(arguments[0]) needs swift-roost \(minimumFramework) or later; this app resolved \(resolved).",
            takeaways: ["Run \(.command("swift package update swift-roost")), then try again."]
        ))
        throw ExitCode.failure
    }
    if database { try DevDatabase.start(root: context.root, appName: context.appName) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.currentDirectoryURL = URL(fileURLWithPath: context.root)
    process.arguments = ["swift", "run", context.appName] + arguments
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 { throw ExitCode.failure }
}

/// Compares the numeric parts of two release versions, such as `2.3.0` and `2.4.0`.
func isVersion(_ version: String, olderThan other: String) -> Bool {
    func parts(_ version: String) -> [Int] { version.split(separator: ".").map { Int($0) ?? 0 } }
    return parts(version).lexicographicallyPrecedes(parts(other))
}
