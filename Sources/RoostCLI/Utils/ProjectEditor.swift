import Foundation

/// Only edit explicit insertion points in a generated app. Handwritten files
/// remain owned by the developer, and an unsupported structure fails before generation.
enum ProjectEditor {
    struct MissingMarker: Error, CustomStringConvertible {
        let marker: String
        var description: String {
            marker == "services"
                ? "Add 'var services: [any Service] { [\n        // roost:services\n    ] }' to App.swift, then rerun the generator."
                : "Add '// roost:\(marker)' inside App.swift's \(marker) declaration, then rerun the generator."
        }
    }

    static func registeredApp(in context: ProjectContext, routes: [String], plugs: [String] = [], services: [String] = []) throws -> (String, String) {
        let path = "Sources/\(context.appName)/App.swift"
        let full = (context.root as NSString).appendingPathComponent(path)
        var content = try String(contentsOfFile: full, encoding: .utf8)
        for (kind, additions) in [("routes", routes), ("plugs", plugs), ("services", services)] where !additions.isEmpty {
            let marker = "// roost:\(kind)"
            guard let range = content.range(of: marker) else { throw MissingMarker(marker: kind) }
            // Indent additions like the marker line.
            let lineStart = content[..<range.lowerBound].lastIndex(of: "\n").map(content.index(after:)) ?? content.startIndex
            let indent = "\n" + content[lineStart..<range.lowerBound]
            content = content.replacingOccurrences(of: marker, with: additions.joined(separator: indent) + indent + marker)
        }
        return (full, content)
    }

    static func nextMigration(in root: String, description: String, offset: Int = 0) -> String {
        let directory = ProjectDiscovery.migrationsDir(root: root)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        let latest = files.compactMap { Int64($0.split(separator: "_").first ?? "") }.max() ?? 0
        // Spectro migration versions use Unix seconds, not calendar timestamps.
        let now = Int64(Date().timeIntervalSince1970)
        return "\(max(now, latest + 1) + Int64(offset))_\(description).sql"
    }
}
