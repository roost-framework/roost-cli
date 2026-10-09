import ArgumentParser
import Foundation
import CoreFoundation
@preconcurrency import Noora

#if os(Linux)
let streamSocket = Int32(SOCK_STREAM.rawValue)
#else
let streamSocket = SOCK_STREAM
#endif

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the Roost project (compiles Tailwind CSS if configured, then runs swift build)"
    )

    @Flag(name: .long, help: "Watch for file changes and rebuild automatically")
    var watch: Bool = false

    @Option(name: .long, help: "Port to run the server on (watch mode only)")
    var port: Int?

    func run() async throws {
        let cwd = ProjectDiscovery.findRoot() ?? FileManager.default.currentDirectoryPath

        if watch {
            try await runWatchMode(cwd: cwd)
        } else {
            try await runBuild(cwd: cwd)
        }
    }

    // MARK: - Standard Build

    private func runBuild(cwd: String) async throws {
        // If Tailwind is configured, compile CSS first
        if let tailwindBinary = Self.tailwindBinary(in: cwd) {
            RoostUI.noora.info(.alert("Compiling Tailwind CSS..."))

            let tailwindProcess = Process()
            tailwindProcess.executableURL = URL(fileURLWithPath: tailwindBinary)
            tailwindProcess.arguments = [
                "-i", "Public/css/input.css",
                "-o", "Public/css/app.css",
                "--minify",
            ]
            tailwindProcess.currentDirectoryURL = URL(fileURLWithPath: cwd)

            try tailwindProcess.run()
            tailwindProcess.waitUntilExit()

            guard tailwindProcess.terminationStatus == 0 else {
                RoostUI.noora.error(.alert(
                    "Tailwind CSS compilation failed.",
                    takeaways: ["Check Public/css/input.css for errors."]
                ))
                throw ExitCode.failure
            }

            RoostUI.noora.success(.alert("Tailwind CSS compiled"))
        }

        // Run swift build
        RoostUI.noora.info(.alert("Running \(.command("swift build"))..."))

        let buildProcess = Process()
        buildProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        buildProcess.arguments = ["swift", "build"]
        buildProcess.currentDirectoryURL = URL(fileURLWithPath: cwd)

        try buildProcess.run()
        buildProcess.waitUntilExit()

        guard buildProcess.terminationStatus == 0 else {
            RoostUI.noora.error(.alert(
                "swift build failed.",
                takeaways: ["Check the compiler output above for errors."]
            ))
            throw ExitCode.failure
        }

        RoostUI.noora.success(.alert("Build succeeded"))
    }

    // MARK: - Watch Mode

    private func runWatchMode(cwd: String) async throws {
        guard let root = ProjectDiscovery.findRoot(from: cwd),
              let appName = ProjectDiscovery.findAppName(in: root)
        else {
            RoostUI.noora.error(.alert("Could not find Roost project"))
            throw ExitCode.failure
        }

        let binaryPath = try ProcessManager.binaryPath(product: appName, root: root)
        let processManager = ProcessManager()

        // Before the SIGINT handler, so Ctrl+C still stops a slow container start.
        try DevDatabase.start(root: root, appName: appName)

        let explicitPort = self.port ?? ProcessInfo.processInfo.environment["ROOST_PORT"].flatMap(Int.init)
        let port = explicitPort ?? Self.freePort(from: 8080)
        if port != explicitPort ?? 8080 {
            print("[roost] Port 8080 is in use; using \(port).")
        }

        // Handle Ctrl+C cleanly via DispatchSource
        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            print("")
            print("[roost] Shutting down...")
            processManager.stopAll()
            Foundation.exit(0)
        }
        sigintSource.resume()

        // Initial build
        print("[roost] Building...")
        let startTime = CFAbsoluteTimeGetCurrent()
        let success = runBuildSync(cwd: cwd)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        if success {
            print("[roost] Build complete. (\(String(format: "%.1f", duration))s)")

            // Start Tailwind watch if configured
            if let tailwindBinary = Self.tailwindBinary(in: cwd) {
                processManager.startTailwind(binary: tailwindBinary, cwd: cwd)
            }

            // Start server
            processManager.startServer(binary: binaryPath, port: port, cwd: root)
            print("[roost] Server started on http://127.0.0.1:\(port)")
        } else {
            print("[roost] Build failed. Watching for changes to retry...")
        }

        // Watch for changes
        let sourcesDir = (cwd as NSString).appendingPathComponent("Sources")
        print("[roost] Watching for changes...")

        let watcher = FileWatcher(
            paths: [sourcesDir],
            extensions: ["swift", "esw", "hesw", "heex"],
            debounceInterval: 0.3
        ) { changedFiles in
            for file in changedFiles {
                let relative = file.replacingOccurrences(of: cwd + "/", with: "")
                print("[roost] Changed: \(relative)")
            }

            print("[roost] Rebuilding...")
            let rebuildStart = CFAbsoluteTimeGetCurrent()

            let rebuildSuccess = self.runBuildSync(cwd: cwd)
            let rebuildDuration = CFAbsoluteTimeGetCurrent() - rebuildStart

            if rebuildSuccess {
                print("[roost] Build complete. (\(String(format: "%.1f", rebuildDuration))s)")
                processManager.stopServer()
                processManager.startServer(binary: binaryPath, port: port, cwd: root)
                print("[roost] Server restarted.")
            } else {
                print("[roost] Build failed. The previous server is still running. Fix the error and save to retry.")
            }
        }

        watcher.start() // Blocks until process exits
    }

    // MARK: - Port

    /// The first port from `start` that nothing on 127.0.0.1 accepts connections on.
    static func freePort(from start: Int) -> Int {
        (start..<start + 100).first { !isListening(on: $0) } ?? start
    }

    private static func isListening(on port: Int) -> Bool {
        let fd = socket(AF_INET, streamSocket, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    // MARK: - Tailwind

    /// The project's Tailwind binary, when it also has a `Public/css/input.css` entry point.
    private static func tailwindBinary(in cwd: String) -> String? {
        let binary = (cwd as NSString).appendingPathComponent(".build/tailwindcss")
        let input = (cwd as NSString).appendingPathComponent("Public/css/input.css")
        guard FileManager.default.fileExists(atPath: binary),
              let css = try? String(contentsOfFile: input, encoding: .utf8) else { return nil }
        if css.contains("@tailwind base") {
            print("[roost] Public/css/input.css uses Tailwind v3 directives, which Tailwind v4 ignores. Replace them with: @import \"tailwindcss\";")
        }
        return binary
    }

    // MARK: - Synchronous Build Helper

    private func runBuildSync(cwd: String) -> Bool {
        // Tailwind compilation if configured
        if let tailwindBinary = Self.tailwindBinary(in: cwd) {
            let tw = Process()
            tw.executableURL = URL(fileURLWithPath: tailwindBinary)
            tw.arguments = ["-i", "Public/css/input.css", "-o", "Public/css/app.css", "--minify"]
            tw.currentDirectoryURL = URL(fileURLWithPath: cwd)
            do {
                try tw.run()
                tw.waitUntilExit()
                if tw.terminationStatus != 0 { return false }
            } catch {
                return false
            }
        }

        // Swift build
        let build = Process()
        build.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        build.arguments = ["swift", "build"]
        build.currentDirectoryURL = URL(fileURLWithPath: cwd)
        do {
            try build.run()
            build.waitUntilExit()
            return build.terminationStatus == 0
        } catch {
            return false
        }
    }
}
